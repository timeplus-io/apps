CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.src_player_actions
(
    user_id string DEFAULT concat('usr_', to_string(rand64(1) % 20000)),
    session_id string DEFAULT concat('sess_', to_string(rand64(2) % 1000)),
    timestamp string DEFAULT format_datetime(now64(), '%Y-%m-%dT%H:%i:%s.%fZ'),
    event_type enum8('match_start' = 1, 'item_pickup' = 2, 'player_elimination' = 3, 'match_end' = 4) DEFAULT multi_if(
        rand(3) % 100 < 10, 'match_start',
        rand(3) % 100 < 50, 'item_pickup',
        rand(3) % 100 < 90, 'player_elimination',
        'match_end'
    ),
    game_mode enum8('battle_royale' = 1, 'team_deathmatch' = 2, 'capture_the_flag' = 3) DEFAULT multi_if(
        rand(4) % 100 < 75, 'battle_royale',
        rand(4) % 100 < 95, 'team_deathmatch',
        'capture_the_flag'
    ),
    match_id string DEFAULT concat('match_', to_string(rand(5) % 900 + 100)),
    event_data string DEFAULT concat(
        '{',
        '"placement":', to_string(multi_if(event_type = 'match_end', abs(to_int32(rand_normal(50, 25))) + 1, 0)), ',',
        '"kills":', to_string(multi_if(event_type IN ('player_elimination', 'match_end'), rand_poisson(2), 0)), ',',
        '"damage_dealt":', to_string(multi_if(event_type IN ('player_elimination', 'match_end'), to_int32(exp(rand_normal(6.5, 1.2))), 0)), ',',
        '"survival_time":', to_string(multi_if(event_type = 'match_end', to_int32(rand_uniform(300, 1200)), 0)), ',',
        '"result":"', to_string(multi_if(event_type = 'match_end', array_element(['win', 'loss'], (rand(6) % 2) + 1), 'na')), '",',
        '"items_used":["', array_element(['med_kit', 'shield_potion', 'grenade', 'smoke_bomb', 'bandages', ''], (rand(7) % 6) + 1), '","', array_element(['med_kit', 'shield_potion', 'grenade', ''], (rand(8) % 4) + 1), '"],',
        '"location_final":{',
            '"x":', to_string(round(rand_uniform(0, 1500), 2)), ',',
            '"y":', to_string(round(rand_uniform(0, 1500), 2)),
        '}',
        '}'
    ),
    device_info string DEFAULT concat(
        '{',
        '"platform":"', array_element(['mobile_ios', 'mobile_android', 'pc_windows', 'console_ps5', 'console_xbox'], (rand(9) % 5) + 1), '",',
        '"device_model":"', array_element(['iPhone_15_Pro', 'Samsung_S24', 'Gaming_PC_Rig', 'PlayStation_5', 'Xbox_Series_X'], (rand(10) % 5) + 1), '",',
        '"os_version":"', array_element(['iOS_17.1', 'Android_14', 'Windows_11', 'PS5_OS_9.0', 'Xbox_OS_10.0'], (rand(11) % 5) + 1), '",',
        '"app_version":"', array_element(['2.4.1', '2.4.0', '2.3.5', '2.2.0'], (rand(12) % 4) + 1), '"',
        '}'
    )
)
SETTINGS eps = {{ .Config.player_actions_eps }};
