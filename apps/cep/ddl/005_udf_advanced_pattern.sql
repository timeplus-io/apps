CREATE OR REPLACE AGGREGATE FUNCTION cep_advanced_pattern(time datetime64(3), event string, _tp_delta int8) RETURNS string LANGUAGE JAVASCRIPT AS $${
  has_customized_emit: true,

  initialize: function () {
    this.events = [];
    this.patterns = new Map();
    this.fsm_states = new Map();
    this.match_events = [];
    this.statistics = {
      total_events: 0,
      patterns_detected: 0,
      pattern_stats: new Map()
    };

    // Initialize default patterns
    this._initializeDefaultPatterns();
  },

  // Initialize common CEP patterns
  _initializeDefaultPatterns: function() {
    // Simple sequence pattern: A -> B -> A
    this.addPattern('sequence_ABA', {
      type: 'sequence',
      events: ['A', 'B', 'A'],
      timeWindow: 10000, // 10 seconds
      description: 'Sequential pattern A->B->A'
    });

    // Threshold pattern: 3 or more 'A' events
    this.addPattern('threshold_A', {
      type: 'threshold',
      eventType: 'A',
      count: 3,
      timeWindow: 5000, // 5 seconds
      description: 'At least 3 A events within 5 seconds'
    });

    // Absence pattern: A followed by B, but no C within time window
    this.addPattern('absence_AC', {
      type: 'absence',
      trigger: 'A',
      expected: 'C',
      timeWindow: 3000, // 3 seconds
      description: 'A event without C event within 3 seconds'
    });

    // Alternating pattern: A and B alternating
    this.addPattern('alternating_AB', {
      type: 'alternating',
      events: ['A', 'B'],
      minOccurrences: 3,
      timeWindow: 8000,
      description: 'Alternating A and B events'
    });

    // Complex condition pattern
    this.addPattern('complex_condition', {
      type: 'custom',
      condition: (events) => {
        const recent = events.slice(-10); // Last 10 events
        for (let i = 0; i < recent.length - 3; i++) {
          if (recent[i].event === 'A') {
            let bCount = 0;
            let j = i + 1;
            while (j < recent.length && recent[j].event === 'B') {
              bCount++;
              j++;
            }
            if (bCount >= 2 && j < recent.length && recent[j].event === 'C') {
              return {
                matched: true,
                events: recent.slice(i, j + 1),
                description: `A followed by ${bCount} B's and C`
              };
            }
          }
        }
        return { matched: false };
      },
      timeWindow: 15000,
      description: 'A followed by 2+ B events, then C'
    });
  },

  // Add a new pattern
  addPattern: function(name, pattern) {
    this.patterns.set(name, pattern);
    this.fsm_states.set(name, this._initializePatternState(pattern));
    this.statistics.pattern_stats.set(name, {
      matches: 0,
      partial_matches: 0,
      resets: 0
    });
    console.log(`📋 Added pattern '${name}': ${pattern.description}`);
  },

  // Remove a pattern
  removePattern: function(name) {
    this.patterns.delete(name);
    this.fsm_states.delete(name);
    this.statistics.pattern_stats.delete(name);
    console.log(`🗑️ Removed pattern '${name}'`);
  },

  // Initialize state for a specific pattern
  _initializePatternState: function(pattern) {
    switch (pattern.type) {
      case 'sequence':
        return { currentStep: 0, matchedEvents: [], lastEventTime: null };
      case 'threshold':
        return { eventCount: 0, eventTimes: [], matchedEvents: [] };
      case 'absence':
        return { triggerEvent: null, triggerTime: null, waitingForExpected: false };
      case 'alternating':
        return { sequence: [], expectedNext: pattern.events[0], occurrences: 0 };
      case 'custom':
        return { lastProcessedIndex: 0 };
      default:
        return {};
    }
  },

  // Reset state for a specific pattern
  _resetPatternState: function(name) {
    const pattern = this.patterns.get(name);
    this.fsm_states.set(name, this._initializePatternState(pattern));
    const stats = this.statistics.pattern_stats.get(name);
    if (stats) {
      stats.resets++;
    }
  },

  // Main processing function
  process: function (Time, Event) {
    console.log(`📥 Processing batch: ${Event.length} events`);

    for (let i = 0; i < Event.length; i++) {
      const event = {
        time: Time[i],
        event: Event[i],
        index: this.statistics.total_events
      };

      this.events.push(event);
      this.statistics.total_events++;

      console.log(`[${new Date(event.time).toLocaleTimeString()}] Event: ${event.event}`);

      // Process event through all patterns
      this.patterns.forEach((pattern, name) => {
        this._processEventForPattern(event, name, pattern);
      });

      // Clean old events (keep only last 1000 events for memory management)
      if (this.events.length > 1000) {
        this.events = this.events.slice(-500);
      }
    }

    return this.match_events.length;
  },

  // Process a single event for a specific pattern
  _processEventForPattern: function(event, patternName, pattern) {
    const state = this.fsm_states.get(patternName);
    const currentTime = event.time;

    switch (pattern.type) {
      case 'sequence':
        this._processSequencePattern(event, patternName, pattern, state, currentTime);
        break;
      case 'threshold':
        this._processThresholdPattern(event, patternName, pattern, state, currentTime);
        break;
      case 'absence':
        this._processAbsencePattern(event, patternName, pattern, state, currentTime);
        break;
      case 'alternating':
        this._processAlternatingPattern(event, patternName, pattern, state, currentTime);
        break;
      case 'custom':
        this._processCustomPattern(event, patternName, pattern, state);
        break;
    }
  },

  // Process sequence pattern (A -> B -> C)
  _processSequencePattern: function(event, patternName, pattern, state, currentTime) {
    const expectedEvent = pattern.events[state.currentStep];

    if (event.event === expectedEvent) {
      state.matchedEvents.push(event);
      state.currentStep++;
      state.lastEventTime = currentTime;

      console.log(`🔄 Pattern '${patternName}' progress: ${state.currentStep}/${pattern.events.length}`);

      if (state.currentStep >= pattern.events.length) {
        // Pattern completed
        this._emitPatternMatch(patternName, pattern, state.matchedEvents, 'SEQUENCE_COMPLETE');
        this._resetPatternState(patternName);
      }
    } else {
      // Check if we need to reset or if this could be the start of a new sequence
      if (state.currentStep > 0) {
        this._resetPatternState(patternName);
        // Try processing this event as potential start of new sequence
        this._processSequencePattern(event, patternName, pattern, this.fsm_states.get(patternName), currentTime);
      }
    }

    // Check time window
    if (state.lastEventTime && (currentTime - state.lastEventTime) > pattern.timeWindow) {
      this._resetPatternState(patternName);
    }
  },

  // Process threshold pattern (N events of type X within time window)
  _processThresholdPattern: function(event, patternName, pattern, state, currentTime) {
    if (event.event === pattern.eventType) {
      state.eventTimes.push(currentTime);
      state.eventCount++;
      state.matchedEvents.push(event);

      // Remove events outside time window
      const cutoffTime = currentTime - pattern.timeWindow;
      let validIndex = 0;
      while (validIndex < state.eventTimes.length && state.eventTimes[validIndex] < cutoffTime) {
        validIndex++;
      }

      if (validIndex > 0) {
        state.eventTimes = state.eventTimes.slice(validIndex);
        state.matchedEvents = state.matchedEvents.slice(validIndex);
        state.eventCount = state.eventTimes.length;
      }

      console.log(`📊 Pattern '${patternName}' count: ${state.eventCount}/${pattern.count}`);

      if (state.eventCount >= pattern.count) {
        this._emitPatternMatch(patternName, pattern, state.matchedEvents, 'THRESHOLD_REACHED');
        // Reset after detection
        this._resetPatternState(patternName);
      }
    }
  },

  // Process absence pattern (A without B within time window)
  _processAbsencePattern: function(event, patternName, pattern, state, currentTime) {
    if (event.event === pattern.trigger) {
      state.triggerEvent = event;
      state.triggerTime = currentTime;
      state.waitingForExpected = true;
      console.log(`⏳ Pattern '${patternName}' waiting for '${pattern.expected}' within ${pattern.timeWindow}ms`);
    } else if (state.waitingForExpected && event.event === pattern.expected) {
      // Expected event occurred, reset
      state.waitingForExpected = false;
      state.triggerEvent = null;
      state.triggerTime = null;
    }

    // Check if time window expired without expected event
    if (state.waitingForExpected && (currentTime - state.triggerTime) > pattern.timeWindow) {
      this._emitPatternMatch(patternName, pattern, [state.triggerEvent], 'ABSENCE_DETECTED');
      state.waitingForExpected = false;
      state.triggerEvent = null;
      state.triggerTime = null;
    }
  },

  // Process alternating pattern (A, B, A, B, ...)
  _processAlternatingPattern: function(event, patternName, pattern, state, currentTime) {
    if (event.event === state.expectedNext) {
      state.sequence.push(event);

      // Determine next expected event
      const currentIndex = pattern.events.indexOf(state.expectedNext);
      state.expectedNext = pattern.events[(currentIndex + 1) % pattern.events.length];

      // Check if completed enough alternations
      if (state.sequence.length >= pattern.minOccurrences * pattern.events.length) {
        state.occurrences++;
        this._emitPatternMatch(patternName, pattern, state.sequence, 'ALTERNATING_COMPLETE');
        this._resetPatternState(patternName);
      }
    } else {
      // Reset on wrong event
      if (state.sequence.length > 0) {
        this._resetPatternState(patternName);
        // Try this event as potential start
        this._processAlternatingPattern(event, patternName, pattern, this.fsm_states.get(patternName), currentTime);
      }
    }

    // Clean old events in sequence based on time window
    if (state.sequence.length > 0) {
      const cutoffTime = currentTime - pattern.timeWindow;
      state.sequence = state.sequence.filter(e => e.time >= cutoffTime);
      if (state.sequence.length === 0) {
        this._resetPatternState(patternName);
      }
    }
  },

  // Process custom pattern
  _processCustomPattern: function(event, patternName, pattern, state) {
    const result = pattern.condition(this.events);
    if (result.matched) {
      this._emitPatternMatch(patternName, pattern, result.events, `CUSTOM: ${result.description}`);
    }
  },

  // Emit pattern match
  _emitPatternMatch: function(patternName, pattern, events, matchType) {
    const match = {
      patternName,
      patternDescription: pattern.description,
      matchType,
      events: events.map(e => ({ time: e.time, event: e.event })),
      timestamp: new Date().toISOString(),
      eventSequence: events.map(e => e.event).join(' → ')
    };

    this.match_events.push(JSON.stringify(match));
    this.statistics.patterns_detected++;

    const stats = this.statistics.pattern_stats.get(patternName);
    if (stats) {
      stats.matches++;
    }

    console.log(`🎉 PATTERN DETECTED: '${patternName}' - ${matchType}`);
    console.log(`   Sequence: ${match.eventSequence}`);
    console.log(`   Events: ${events.length}, Time span: ${events[events.length-1].time - events[0].time}ms`);
  },

  // Get comprehensive statistics
  getStatistics: function() {
    const patternStats = {};
    this.statistics.pattern_stats.forEach((stats, name) => {
      patternStats[name] = {
        ...stats,
        pattern: this.patterns.get(name).description
      };
    });

    return {
      total_events: this.statistics.total_events,
      patterns_detected: this.statistics.patterns_detected,
      detection_rate: this.statistics.total_events > 0
        ? ((this.statistics.patterns_detected / this.statistics.total_events) * 100).toFixed(2) + '%'
        : '0%',
      active_patterns: this.patterns.size,
      pattern_statistics: patternStats,
      events_in_memory: this.events.length
    };
  },

  // Print detailed statistics
  printStatistics: function() {
    const stats = this.getStatistics();
    console.log('\n' + '='.repeat(60));
    console.log('📊 CEP PATTERN RECOGNITION STATISTICS');
    console.log('='.repeat(60));
    console.log(`Total Events Processed: ${stats.total_events}`);
    console.log(`Patterns Detected: ${stats.patterns_detected}`);
    console.log(`Detection Rate: ${stats.detection_rate}`);
    console.log(`Active Patterns: ${stats.active_patterns}`);
    console.log(`Events in Memory: ${stats.events_in_memory}`);
    console.log();

    console.log('📋 Pattern Details:');
    Object.entries(stats.pattern_statistics).forEach(([name, stat]) => {
      console.log(`  ${name}:`);
      console.log(`    Description: ${stat.pattern}`);
      console.log(`    Matches: ${stat.matches}`);
      console.log(`    Partial Matches: ${stat.partial_matches}`);
      console.log(`    Resets: ${stat.resets}`);
    });
    console.log('='.repeat(60));
  },

  // Finalize and return results
  finalize: function () {
    const result = [...this.match_events];

    // Print statistics before clearing
    if (result.length > 0) {
      console.log(`\n🎯 Finalizing: ${result.length} pattern matches detected`);
      result.forEach((match, index) => {
        console.log(`  ${index + 1}. ${match}`);
      });
    }

    // Clear matches for next batch
    this.match_events = [];

    return result;
  },

  // Utility: Clear all events and reset
  reset: function() {
    this.events = [];
    this.match_events = [];
    this.patterns.forEach((pattern, name) => {
      this._resetPatternState(name);
    });
    this.statistics = {
      total_events: 0,
      patterns_detected: 0,
      pattern_stats: new Map()
    };
    this.patterns.forEach((pattern, name) => {
      this.statistics.pattern_stats.set(name, {
        matches: 0,
        partial_matches: 0,
        resets: 0
      });
    });
    console.log('🔄 CEP system reset');
  },

  // Utility: Get current pattern states
  getPatternStates: function() {
    const states = {};
    this.fsm_states.forEach((state, name) => {
      states[name] = { ...state };
    });
    return states;
  }
}$$
