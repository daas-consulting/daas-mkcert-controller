# daas-mkcert-controller
Servicio Docker para desarrollo local que detecta dominios *.localhost usados por Traefik, genera certificados TLS válidos con mkcert y mantiene la configuración TLS sincronizada en caliente, sin reiniciar Traefik ni usar CAs públicas.
