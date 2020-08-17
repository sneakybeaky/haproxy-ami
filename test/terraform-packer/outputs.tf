output "instance_id" {
  value = "${aws_instance.haproxy.id}"
}

output "public_ip" {
  value = "${aws_instance.haproxy.public_ip}"
}

output "stats_url" {
  value = "http://${aws_instance.haproxy.public_ip}:${var.stats_port}/stats"
}

output "node_export_url" {
  value = "http://${aws_instance.haproxy.public_ip}:${var.node_export_port}/metrics"
}

output "haproxy_exporter_url" {
  value = "http://${aws_instance.haproxy.public_ip}:${var.haproxy_exporter_port}/metrics"
}

output "bbc_healthcheck_url" {
  value = "http://${aws_instance.haproxy.public_ip}:${var.bbc_healthcheck_port}/bbc_site_alive"
}