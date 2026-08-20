output "vm_public_ip" {
  description = "Public IP of the Civo TURN server — use this to SSH in and run tests"
  value       = civo_instance.turn_server.public_ip
}

output "ssh_command" {
  description = "Ready-to-use SSH command to connect to the TURN server"
  value       = "ssh civo@${civo_instance.turn_server.public_ip}"
}

output "turn_uri" {
  description = "TURN URI to use in your WebRTC ICE server config"
  value       = "turn:${civo_instance.turn_server.public_ip}:3478"
}

output "webrtc_ice_config" {
  description = "Paste this into your WebRTC app's ICE server config"
  value = jsonencode({
    iceServers = [
      {
        urls     = "turn:${civo_instance.turn_server.public_ip}:3478"
        username = "poctest"
        credential = var.turn_secret
      }
    ]
  })
  sensitive = true
}
