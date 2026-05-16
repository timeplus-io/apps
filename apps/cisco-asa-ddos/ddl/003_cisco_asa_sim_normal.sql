CREATE RANDOM STREAM {{ .DB }}.cisco_asa_sim_normal (
    timestamp datetime64(3) DEFAULT now64(3),
    device_name string DEFAULT 'asa-fw01',
    src_ip string DEFAULT '{{ .Config.attacker_src_ip }}',
    dst_ip string DEFAULT concat(
        '10.',
        to_string((rand(1) % 256)), '.',
        to_string((rand(2) % 256)), '.',
        to_string((rand(3) % 256))
    ),
    message_id string DEFAULT multi_if(
        (rand(4) % 100) <= 60, '302014',
        '302016'
    ),
    severity int8 DEFAULT 6,
    src_port uint16 DEFAULT (rand(5) % 30000) + 32768,
    dst_port uint16 DEFAULT multi_if(
        (rand(6) % 100) <= 30, 443,
        (rand(7) % 100) <= 50, 80,
        (rand(8) % 100) <= 65, 22,
        (rand(9) % 100) <= 75, 53,
        (rand(10) % 65535) + 1
    ),
    protocol string DEFAULT multi_if(message_id = '302014', 'TCP', 'UDP'),
    src_interface string DEFAULT 'outside',
    dst_interface string DEFAULT 'inside',
    connection_id uint32 DEFAULT rand(11),
    bytes_sent uint32 DEFAULT (rand(12) % 50000) + 1000,
    duration_seconds uint16 DEFAULT (rand(13) % 10) + 1,
    duration string DEFAULT concat('00:00:', lpad(to_string(duration_seconds), 2, '0')),
    tcp_flags string DEFAULT array_element(['TCP FINs', 'TCP RSTs', 'TCP SYNs', 'TCP data'], (rand(14) % 4) + 1),
    priority uint8 DEFAULT 190,
    message_text string DEFAULT multi_if(
        message_id = '302014', concat(
            'Teardown TCP connection ', to_string(connection_id),
            ' for ', src_interface, ':', src_ip, '/', to_string(src_port),
            ' to ', dst_interface, ':', dst_ip, '/', to_string(dst_port),
            ' duration ', duration,
            ' bytes ', to_string(bytes_sent), ' ', tcp_flags
        ),
        concat(
            'Teardown UDP connection ', to_string(connection_id),
            ' for ', src_interface, ':', src_ip, '/', to_string(src_port),
            ' to ', dst_interface, ':', dst_ip, '/', to_string(dst_port),
            ' duration ', duration,
            ' bytes ', to_string(bytes_sent)
        )
    ),
    log_message string DEFAULT concat(
        '<', to_string(priority), '>',
        format_datetime(timestamp, '%b %e %H:%M:%S'),
        ' ', device_name,
        ' %ASA-', to_string(severity), '-', message_id, ': ',
        message_text
    )
) SETTINGS eps = {{ .Config.sim_normal_eps }}
