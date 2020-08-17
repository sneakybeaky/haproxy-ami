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

output "dtax_healthcheck_url" {
  value = "http://${aws_instance.haproxy.public_ip}:${var.dtax_healthcheck_port}/dtax_site_alive"
}

output "itax_healthcheck_url" {
  value = "http://${aws_instance.haproxy.public_ip}:${var.itax_healthcheck_port}/itax_site_alive"
}

output "haproxy_exporter_url" {
  value = "http://${aws_instance.haproxy.public_ip}:${var.haproxy_exporter_port}/metrics"
}
