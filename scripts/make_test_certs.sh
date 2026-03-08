#!/bin/bash
# Script para gerar certificados auto-assinados para testes TLS
# Uso: ./scripts/make_test_certs.sh

set -e

CERT_DIR="WebSocket/Tests/certs"
DAYS=365
BITS=2048

echo "🔐 Gerando certificados de teste para TLS..."

# Criar diretório se não existir
mkdir -p "$CERT_DIR"

# Gerar chave privada
echo "Gerando chave privada..."
openssl genrsa -out "$CERT_DIR/server.key.pem" $BITS

# Gerar certificado auto-assinado
echo "Gerando certificado auto-assinado..."
openssl req -new -x509 \
    -key "$CERT_DIR/server.key.pem" \
    -out "$CERT_DIR/server.cert.pem" \
    -days $DAYS \
    -subj "/C=BR/ST=SP/L=SaoPaulo/O=WebSocketLean/CN=localhost" \
    -addext "subjectAltName = DNS:localhost,IP:127.0.0.1,IP:::1"

# Gerar certificado de cliente (opcional)
echo "Gerando certificado de cliente..."
openssl genrsa -out "$CERT_DIR/client.key.pem" $BITS
openssl req -new -x509 \
    -key "$CERT_DIR/client.key.pem" \
    -out "$CERT_DIR/client.cert.pem" \
    -days $DAYS \
    -subj "/C=BR/ST=SP/L=SaoPaulo/O=WebSocketLean/CN=client"

# Definir permissões apropriadas
chmod 600 "$CERT_DIR"/*.key.pem
chmod 644 "$CERT_DIR"/*.cert.pem

echo "✅ Certificados criados em $CERT_DIR:"
ls -la "$CERT_DIR"

echo ""
echo "Para testar com openssl:"
echo "  openssl s_client -connect localhost:9443 -cert $CERT_DIR/client.cert.pem -key $CERT_DIR/client.key.pem"
echo ""
echo "Para verificar certificado:"
echo "  openssl x509 -in $CERT_DIR/server.cert.pem -text -noout"