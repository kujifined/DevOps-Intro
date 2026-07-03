# Teardown

## Hugging Face Space

The Space can be deleted from:

`https://huggingface.co/spaces/$HF_USERNAME/$HF_SPACE_NAME/settings`

It can also be left public for the lab because the free tier costs $0.

## Cloudflare Tunnel

The quick tunnel is ephemeral. Stop it with `Ctrl+C`.

The public `trycloudflare.com` URL becomes invalid after `cloudflared` exits.

## Local container

```bash
docker ps
docker stop <container-id>
```
