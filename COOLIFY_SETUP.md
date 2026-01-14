# Configuração para Coolify - Problema de Conexão EventSource/Mercure

## Problema

Quando o painel é executado no Coolify, mesmo com os containers na mesma rede Docker, a chamada de senhas não funciona porque o **EventSource (Server-Sent Events)** é executado no **navegador do cliente**, não no servidor.

O navegador precisa acessar o Mercure Hub através de uma **URL pública acessível**, não através de nomes de host internos do Docker.

## Soluções

### Solução 1: Configurar URL Pública do Mercure (Recomendado)

O Mercure Hub deve estar acessível através de uma URL pública. No Coolify:

1. **Exponha o serviço Mercure publicamente** através de um domínio/subdomínio
2. **Configure a URL do Mercure** no backend para usar essa URL pública
3. Certifique-se de que o **CORS está configurado** no Mercure para aceitar requisições do domínio do painel

**Exemplo de configuração no backend:**
```env
MERCURE_PUBLIC_URL=https://mercure.seudominio.com
MERCURE_INTERNAL_URL=http://mercure:80
```

### Solução 2: Usar Proxy Reverso no Nginx

Se o Mercure não pode ser exposto diretamente, configure um proxy reverso no Nginx do painel ou em um proxy separado:

```nginx
location /mercure {
    proxy_pass http://mercure:80;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 86400;
}
```

### Solução 3: Verificar Configuração da Rede no Coolify

1. Certifique-se de que ambos os serviços (painel e backend) estão na mesma rede
2. Verifique se o backend está retornando a URL correta do Mercure na API `/api`
3. A URL do Mercure deve ser acessível do navegador, não apenas entre containers

## Fallback de Polling

O código agora inclui um **fallback automático para polling** caso o EventSource não consiga se conectar após várias tentativas. Isso significa que:

- Se o EventSource funcionar, ele será usado (tempo real)
- Se o EventSource falhar, o sistema automaticamente muda para polling (verifica a cada 3 segundos)
- O painel continuará funcionando mesmo se o Mercure não estiver acessível publicamente

**Nota:** O polling é menos eficiente que o EventSource, mas garante que o painel funcione mesmo em ambientes onde o Mercure não está configurado corretamente.

## Diagnóstico

Com as melhorias implementadas no código, você pode verificar no console do navegador:

1. **Abra o DevTools (F12)** no navegador
2. **Verifique os logs** que mostram:
   - A URL do Mercure obtida da API
   - A URL final usada para conectar
   - Erros de conexão do EventSource

**Mensagens de log esperadas:**
```
Mercure URL from API: /mercure
Final Mercure URL: https://seudominio.com/mercure
Connecting to EventSource: https://seudominio.com/mercure?topic=/unidades/1/painel
EventSource connection opened successfully
```

**Se houver erro:**
```
EventSource error occurred. ReadyState: 2
EventSource connection closed. Attempting to reconnect...
```

## Erro 404 (Not Found) - Endpoint Incorreto

Se você está recebendo um **erro 404**, o problema é que a URL do Mercure está usando o endpoint errado.

**Endpoint correto:** `/.well-known/mercure`  
**Endpoint incorreto:** `/mercure`

O código agora **corrige automaticamente** esse problema, mas você também pode configurar corretamente no backend.

## Erro 502 (Bad Gateway) - Configuração no Coolify

Se você está recebendo um **erro 502** ao tentar conectar ao Mercure, o problema é que o **domínio público não está configurado corretamente** no Coolify para rotear para o container do Mercure.

### Diagnóstico

Pelos logs que você mostrou:
- ✅ O Mercure está rodando e funcionando internamente (porta 3000)
- ✅ O Mercure está recebendo publicações do backend corretamente
- ❌ O domínio `mercure.servicoskayser.com.br` não está roteando para o container

### Solução: Configurar Domínio no Coolify

No Coolify, você precisa configurar o domínio para o serviço Mercure:

1. **Acesse o serviço Mercure no Coolify**
2. **Vá em "Domains" ou "Domínios"**
3. **Adicione o domínio:** `mercure.servicoskayser.com.br`
4. **Configure a porta interna:** `3000` (porta que o Mercure está escutando)
5. **Salve e aguarde o SSL ser configurado automaticamente**

### Verificação

Após configurar o domínio, teste:

1. **Acesse no navegador:** `https://mercure.servicoskayser.com.br/.well-known/mercure`
   - Deve retornar informações do Mercure (não 502)

2. **Teste a conexão EventSource:**
   - Abra o DevTools (F12) no painel
   - Verifique se a conexão EventSource abre com sucesso
   - Os logs devem mostrar: `EventSource connection opened successfully`

### Endpoint Correto do Mercure

O endpoint correto do Mercure é `/.well-known/mercure`, **não** `/mercure`.

O código agora **corrige automaticamente** URLs incorretas:
- Se o backend retornar `/mercure` → será corrigido para `/.well-known/mercure`
- Se o backend retornar apenas `/` → será corrigido para `/.well-known/mercure`

### Configuração do Backend

Certifique-se de que o backend está retornando a URL pública correta na API `/api`:

**Opção 1 - URL completa (recomendado):**
```json
{
  "mercureUrl": "https://mercure.servicoskayser.com.br/.well-known/mercure"
}
```

**Opção 2 - Caminho relativo:**
```json
{
  "mercureUrl": "/.well-known/mercure"
}
```

**Opção 3 - Apenas domínio (será corrigido automaticamente):**
```json
{
  "mercureUrl": "https://mercure.servicoskayser.com.br"
}
```

O painel automaticamente combinará com a URL do servidor configurada e corrigirá para usar o endpoint correto.

### Outras Possíveis Causas

Se mesmo após configurar o domínio ainda houver 502:

1. **Verifique se o container Mercure está na mesma rede** que o proxy do Coolify
2. **Verifique os logs do Traefik/Nginx** do Coolify para ver erros de proxy
3. **Verifique se o Mercure aceita conexões externas** (não apenas localhost)
4. **Verifique o CORS** - o Mercure precisa aceitar requisições do domínio do painel

**Solução temporária:** O código agora detecta erros 502 e automaticamente muda para **polling mode**, então o painel continuará funcionando mesmo com o Mercure offline. No entanto, você deve corrigir o problema do Mercure para ter atualizações em tempo real.

## Checklist

- [ ] Mercure Hub está acessível publicamente (não apenas internamente)
- [ ] URL do Mercure no backend está configurada para URL pública
- [ ] CORS está configurado no Mercure para aceitar requisições do domínio do painel
- [ ] Ambos os serviços estão na mesma rede Docker no Coolify
- [ ] **Servidor Mercure está rodando e respondendo corretamente (não retornando 502)**
- [ ] Verificar logs no console do navegador para diagnosticar problemas
- [ ] Verificar logs do servidor Mercure no Coolify

## Notas Importantes

- O EventSource **não funciona** com URLs internas do Docker (ex: `http://mercure:80`)
- O navegador precisa resolver o hostname, então use domínios públicos ou IPs acessíveis
- Certifique-se de que o protocolo (HTTP/HTTPS) está correto
- Se usar HTTPS, o certificado SSL deve ser válido
