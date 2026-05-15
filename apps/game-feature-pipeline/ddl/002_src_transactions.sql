CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.src_transactions
(
    transaction_id string DEFAULT concat('txn_', to_string(rand64(1))),
    user_id string DEFAULT concat('usr_', to_string(rand64(2) % 20000)),
    session_id string DEFAULT concat('sess_', to_string(rand64(3) % 1000)),
    timestamp datetime64(3) DEFAULT now64(3),
    transaction_type enum8('iap_purchase' = 1, 'subscription' = 2, 'refund' = 3) DEFAULT multi_if(
        rand(4) % 100 < 80, 'iap_purchase',
        rand(4) % 100 < 98, 'subscription',
        'refund'
    ),
    item_category enum8('cosmetic' = 1, 'power_up' = 2, 'loot_box' = 3, 'battle_pass' = 4) DEFAULT array_element(
        ['cosmetic', 'power_up', 'loot_box', 'battle_pass'],
        (rand(5) % 4) + 1
    ),
    item_id string DEFAULT concat(
        array_element(['skin', 'emote', 'booster', 'pack'], (rand(6) % 4) + 1),
        '_',
        array_element(['common', 'rare', 'epic', 'legendary'], (rand(7) % 4) + 1),
        '_',
        array_element(['dragon', 'phoenix', 'reaver', 'starfall'], (rand(8) % 4) + 1)
    ),
    amount_usd float64 DEFAULT array_element([0.99, 4.99, 9.99, 19.99, 49.99, 99.99], (rand(9) % 6) + 1),
    currency_type enum8('real_money' = 1, 'virtual_currency' = 2) DEFAULT multi_if(
        rand(10) % 100 < 90, 'real_money',
        'virtual_currency'
    ),
    payment_method enum8('apple_pay' = 1, 'google_pay' = 2, 'credit_card' = 3, 'paypal' = 4) DEFAULT array_element(
        ['apple_pay', 'google_pay', 'credit_card', 'paypal'],
        (rand(11) % 4) + 1
    ),
    location string DEFAULT concat(
        '{',
        '"country":"', array_element(['US', 'CA', 'GB', 'DE', 'JP', 'AU'], (rand(12) % 6) + 1), '",',
        '"region":"', array_element(['California', 'Texas', 'New York', 'Florida', 'Ontario', 'Quebec', 'England', 'Scotland', 'Bavaria', 'Tokyo', 'New South Wales'], (rand(13) % 11) + 1), '",',
        '"city":"', array_element(['Los Angeles', 'Houston', 'New York City', 'Miami', 'Toronto', 'Montreal', 'London', 'Edinburgh', 'Munich', 'Tokyo', 'Sydney'], (rand(14) % 11) + 1), '",',
        '"latitude":', to_string(round(rand_uniform(30.0, 50.0), 4)), ',',
        '"longitude":', to_string(round(rand_uniform(-125.0, -70.0), 4)),
        '}'
    ),
    device_fingerprint string DEFAULT concat('fp_', lower(hex(rand64(15))))
)
SETTINGS eps = {{ .Config.transactions_eps }};
