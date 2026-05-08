CREATE OR REPLACE AGGREGATE FUNCTION cep_simple_pattern(time datetime64(3), event string, _tp_delta int8) RETURNS string LANGUAGE JAVASCRIPT AS $${
 has_customized_emit: true,

 initialize: function () {
   this.events = [];
   this.pattern = ['A', 'B', 'A'];
   this.match_events = [];
 },

 process: function (Time, Event) {
   console.log(Time, Event);

   for (let i = 0; i < Event.length; i++) {
       const event = {
           time: Time[i],
           event: Event[i]
       }
       this.events.push(event);

       // a simple pattern detection
       if (this.events.length > 3) {
           // get last three events
           const last_three_events = this.events.slice(-3);
           // check if the pattern is present
           if (last_three_events[0].event === this.pattern[0] &&
               last_three_events[1].event === this.pattern[1] &&
               last_three_events[2].event === this.pattern[2]) {
               this.match = true;
               this.match_events.push(JSON.stringify(last_three_events))
           }
       }
   }

   return this.match_events.length;
 },

 finalize: function () {
   const result = this.match_events;
   this.match_events = [];
   return result;
 },
}$$
