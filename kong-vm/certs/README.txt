Place your TLS certificate files here:
  - fullchain.pem   (certificate + chain)
  - privkey.pem     (private key)

You can generate these using Let's Encrypt (certbot) or mkcert for testing.

Example with mkcert:
  mkcert -install
  mkcert mykong123gateway.westus.cloudapp.azure.com
  mv mykong123gateway.westus.cloudapp.azure.com.pem fullchain.pem
  mv mykong123gateway.westus.cloudapp.azure.com-key.pem privkey.pem
