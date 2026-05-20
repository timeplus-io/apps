CREATE VIEW IF NOT EXISTS {{ .DB }}.v_k8s_volumes AS
SELECT
  resource_id,
  region,
  resource_type                                                          AS volume_type,
  state,
  size_units                                                             AS size_gb,
  json_extract_string(tags_json, 'KubernetesCluster')                    AS k8s_cluster,
  json_extract_string(tags_json, 'kubernetes.io/created-for/pvc/namespace') AS k8s_namespace,
  json_extract_string(tags_json, 'kubernetes.io/created-for/pvc/name')   AS k8s_pvc_name,
  json_extract_string(tags_json, 'kubernetes.io/created-for/pv/name')    AS k8s_pv_name,
  json_extract_string(tags_json, 'CSIVolumeName')                        AS csi_volume_name,
  creator,
  snapshot_ts
FROM {{ .DB }}.aws_resources
WHERE service = 'ebs'
  AND (
       position(tags_json, 'kubernetes.io/') > 0
    OR position(tags_json, 'ebs.csi.aws.com/') > 0
    OR position(tags_json, 'KubernetesCluster') > 0
  );
