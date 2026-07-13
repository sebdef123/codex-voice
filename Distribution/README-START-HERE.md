# Codex Voice 2 v1.0.3

## Installation rapide

1. Glisser `Codex Voice 2.app` dans `/Applications`.
2. Lancer l'app, puis accorder la Surveillance de l'entree si macOS le demande.
3. macOS TTS fonctionne immediatement.

## Voxtral Streaming local

Voxtral est optionnel. Sur un Mac Apple Silicon, avec internet, installer `uv` depuis https://docs.astral.sh/uv/ puis lancer `Preparer Voxtral.command` une seule fois. Cette preparation telecharge le modele local et la version testee de la dependance audio.

Ensuite, choisir `Moteur > Voxtral Streaming` dans l'app.

Pour arreter normalement le serveur et liberer ses ressources, choisir `Moteur > macOS TTS`. Rechoisir `Voxtral Streaming` le redemarrera a la prochaine lecture.

En cas de besoin, le serveur peut aussi etre arrete manuellement dans Terminal:

```sh
lsof -tiTCP:8765 -sTCP:LISTEN | while read -r pid; do kill "$pid"; done
```

## Dictionnaire personnel

Au premier lancement, l'app cree un dictionnaire par defaut. Pour retrouver tes corrections sur un autre Mac, utiliser `Exporter le dictionnaire de prononciation...` sur le premier Mac puis `Importer un dictionnaire de prononciation...` sur le second.

## Note Gatekeeper

Cette archive est destinee a un transfert personnel et n'est pas notariee. Si macOS bloque la premiere ouverture, utiliser le menu contextuel `Ouvrir` sur l'app, puis confirmer. Une version pour diffusion large devra etre signee Developer ID et notarisee.
