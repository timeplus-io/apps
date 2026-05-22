CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.cisco_asa_background_gen (
    timestamp datetime64(3) DEFAULT now64(3),
    device_name string DEFAULT concat('asa-fw', lpad(to_string((rand(1) % 26) + 1), 2, '0')),
    message_id string DEFAULT array_element([
        '302013', '302014', '302015', '302016', '302020', '302021',
        '302003', '302033', '302012',
        '305011', '305012',
        '109001', '109005', '109007',
        '113004', '113015',
        '212003', '212004',
        '303002',
        '304004',
        '314004',
        '400013', '400038', '400043', '400044', '400048',
        '502111',
        '713172',
        '718012', '718015', '718019', '718021', '718023',
        '710002', '710003',
        '318107',
        '106001',
        '106015', '106023', '106100',
        '313001', '313004', '313005', '313008', '313009',
        '304003',
        '733102', '733104', '733105',
        '750004',
        '108003',
        '202010',
        '419002',
        '430002',
        '602303', '602304', '702307'
    ], (rand(5) % 57) + 1),
    severity int8 DEFAULT multi_if(
        message_id IN ('106001', '108003'), 2,
        message_id IN ('212003', '212004', '304003', '313005', '318107', '202010', '313001'), 3,
        message_id IN ('106023', '106015', '113015', '313004', '400013', '400038', '400043', '400044', '400048', '733102', '733104', '733105'), 4,
        message_id IN ('502111', '718012', '718015', '750004'), 5,
        message_id IN ('109001', '109005', '109007', '113004', '302003', '302012', '302013', '302014', '302015', '302016', '302020', '302021', '302033', '304004', '305011', '305012', '313008', '313009', '314004', '602303', '602304', '702307', '419002', '430002', '713172'), 6,
        7
    ),
    src_ip string DEFAULT multi_if(
        (rand(6) % 100) <= 60, concat('10.', to_string((rand(7) % 256)), '.', to_string((rand(8) % 256)), '.', to_string((rand(9) % 256))),
        (rand(10) % 100) <= 80, concat('192.168.', to_string((rand(11) % 256)), '.', to_string((rand(12) % 256))),
        (rand(13) % 100) <= 90, concat('172.', to_string((rand(14) % 16) + 16), '.', to_string((rand(15) % 256)), '.', to_string((rand(16) % 256))),
        concat(to_string((rand(17) % 223) + 1), '.', to_string((rand(18) % 256)), '.', to_string((rand(19) % 256)), '.', to_string((rand(20) % 256)))
    ),
    dst_ip string DEFAULT multi_if(
        (rand(21) % 100) <= 40, concat('10.', to_string((rand(22) % 256)), '.', to_string((rand(23) % 256)), '.', to_string((rand(24) % 256))),
        (rand(25) % 100) <= 55, concat('192.168.', to_string((rand(26) % 256)), '.', to_string((rand(27) % 256))),
        (rand(28) % 100) <= 65, concat('172.', to_string((rand(29) % 16) + 16), '.', to_string((rand(30) % 256)), '.', to_string((rand(31) % 256))),
        concat(to_string((rand(32) % 223) + 1), '.', to_string((rand(33) % 256)), '.', to_string((rand(34) % 256)), '.', to_string((rand(35) % 256)))
    ),
    src_port uint16 DEFAULT multi_if(
        (rand(36) % 100) <= 70, (rand(37) % 30000) + 32768,
        (rand(38) % 65535) + 1
    ),
    dst_port uint16 DEFAULT multi_if(
        (rand(39) % 100) <= 30, 443,
        (rand(40) % 100) <= 50, 80,
        (rand(41) % 100) <= 65, 22,
        (rand(42) % 100) <= 75, 3389,
        (rand(43) % 100) <= 85, 53,
        (rand(44) % 100) <= 90, 21,
        (rand(45) % 100) <= 93, 25,
        (rand(46) % 100) <= 95, 3306,
        (rand(47) % 100) <= 97, 5432,
        (rand(48) % 65535) + 1
    ),
    protocol string DEFAULT array_element(['TCP', 'UDP', 'ICMP', 'ESP', 'AH', 'GRE'], multi_if(
        (rand(49) % 100) <= 70, 1,
        (rand(50) % 100) <= 90, 2,
        (rand(51) % 100) <= 97, 3,
        (rand(52) % 3) + 4
    )),
    src_interface string DEFAULT array_element(['outside', 'inside', 'dmz', 'management', 'wan', 'lan'], (rand(53) % 6) + 1),
    dst_interface string DEFAULT array_element(['outside', 'inside', 'dmz', 'management', 'wan', 'lan'], (rand(54) % 6) + 1),
    connection_id uint32 DEFAULT rand(55),
    bytes_sent uint32 DEFAULT multi_if(
        protocol = 'ICMP', rand(56) % 1000,
        protocol = 'UDP', rand(57) % 50000,
        message_id IN ('302020', '302021'), rand(58) % 1000,
        rand(59) % 5000000
    ),
    nat_src_ip string DEFAULT multi_if(
        (rand(64) % 100) <= 50, src_ip,
        concat(to_string((rand(65) % 223) + 1), '.', to_string((rand(66) % 256)), '.', to_string((rand(67) % 256)), '.', to_string((rand(68) % 256)))
    ),
    nat_dst_ip string DEFAULT multi_if(
        (rand(69) % 100) <= 50, dst_ip,
        concat(to_string((rand(70) % 223) + 1), '.', to_string((rand(71) % 256)), '.', to_string((rand(72) % 256)), '.', to_string((rand(73) % 256)))
    ),
    duration_seconds uint16 DEFAULT (rand(81) % 3600),
    duration string DEFAULT concat(
        lpad(to_string(floor(duration_seconds / 3600)), 2, '0'), ':',
        lpad(to_string(floor((duration_seconds % 3600) / 60)), 2, '0'), ':',
        lpad(to_string(duration_seconds % 60), 2, '0')
    ),
    tcp_flags string DEFAULT array_element(['TCP FINs', 'TCP RSTs', 'TCP SYNs', 'TCP data'], (rand(82) % 4) + 1),
    priority uint8 DEFAULT 184 + severity,
    message_text string DEFAULT multi_if(
        message_id = '302013', concat(
            'Built Inbound ', upper(protocol), ' connection ', to_string(connection_id),
            ' for ', src_interface, ':', src_ip, '/', to_string(src_port),
            ' (', nat_src_ip, '/', to_string(src_port), ')',
            ' to ', dst_interface, ':', dst_ip, '/', to_string(dst_port),
            ' (', nat_dst_ip, '/', to_string(dst_port), ')'
        ),
        message_id = '302014', concat(
            'Teardown ', upper(protocol), ' connection ', to_string(connection_id),
            ' for ', src_interface, ':', src_ip, '/', to_string(src_port),
            ' to ', dst_interface, ':', dst_ip, '/', to_string(dst_port),
            ' duration ', duration, ' bytes ', to_string(bytes_sent), ' ', tcp_flags
        ),
        message_id = '302016', concat(
            'Teardown UDP connection ', to_string(connection_id),
            ' for ', src_interface, ':', src_ip, '/', to_string(src_port),
            ' to ', dst_interface, ':', dst_ip, '/', to_string(dst_port),
            ' duration ', duration, ' bytes ', to_string(bytes_sent)
        ),
        concat('Event for message ID ', message_id, ' from ', src_ip, ' to ', dst_ip)
    ),
    log_message string DEFAULT concat(
        '<', to_string(priority), '>',
        format_datetime(timestamp, '%b %e %H:%M:%S'),
        ' ', device_name,
        ' %ASA-', to_string(severity), '-', message_id, ': ',
        message_text
    )
) SETTINGS eps = {{ .Config.background_eps }}
