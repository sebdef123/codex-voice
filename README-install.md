# Codex Voice 2 v1.0.0

Codex Voice 2 est le compagnon menu-bar local de Codex. Il preserve la lecture macOS existante et ajoute Voxtral Streaming local comme moteur global optionnel.

## Contenu

- Lecture automatique des reponses Codex via les transcripts locaux.
- Moteur global au choix: macOS TTS ou Voxtral Streaming local.
- Toutes les voix Voxtral du Lab, avec `fr_female` comme defaut.
- Les longues reponses Voxtral sont segmentees par phrases dans un seul flux afin de proteger la qualite vocale et la memoire du Mac.
- Relecture avec les fleches gauche et droite.
- Arret de la lecture avec Option droite, pratique avec le push-to-talk macOS.
- Dictionnaire de prononciation externe applique uniquement au moteur macOS TTS. Le texte est transmis intact a Voxtral Streaming. Le fichier persistant est `~/Library/Application Support/Codex Voice 2/pronunciations.csv`; il est cree au premier lancement puis n'est jamais ecrase par une mise a jour.
- Logs JSONL avec latence, interruptions et ressources dans `~/Library/Logs/Codex Voice 2/voice-events.jsonl`. Le texte lu est exclu par defaut et peut etre active explicitement depuis le menu pour un diagnostic ponctuel.
- Log du serveur local dans `~/Library/Logs/Codex Voice 2/voxtral-server.log`.

## Build

Depuis ce dossier:

```sh
./build-codex-voice.sh
```

Le script produit puis installe automatiquement:

```text
Codex Voice 2.app
```

L'installation cible est `/Applications/Codex Voice 2.app`. Pour produire seulement le bundle local:

```sh
CODEX_VOICE_SKIP_INSTALL=1 ./build-codex-voice.sh
```

Pour verifier les regressions locales avant une build:

```sh
./test-codex-voice.sh
```

Le test verrouille le filtrage de contenu et le dictionnaire de prononciation, puis verifie la syntaxe du bridge Voxtral.

Lorsque le serveur Voxtral est deja pret, le contrat HTTP streaming peut aussi etre verifie sans lancer l'interface:

```sh
./test-voxtral-protocol.sh
```

Le protocole d'essai d'ecoute et d'interruption est dans `TESTING.md`.

## Installation

Copier `Codex Voice 2.app` dans `/Applications`, puis ouvrir l'app.

macOS demandera probablement les autorisations:

- Confidentialite et securite > Accessibilite
- Confidentialite et securite > Surveillance de l'entree

Si les fleches ne repondent plus apres une nouvelle build, retirer puis rajouter `Codex Voice 2.app` dans Surveillance de l'entree.

Codex Voice 2 utilise le meme bridge Voxtral local que Local Voice Lab, sur le port `8765`. Si un bridge est deja actif, l'app s'y attache. Si elle l'a elle-meme lance, elle l'arrete lorsque le moteur macOS est re-selectionne ou a la fermeture.

## Confidentialite des logs

Par defaut, les logs ne contiennent pas le texte des reponses Codex. Ils conservent les donnees utiles au diagnostic: moteur, voix, longueurs, horodatages, latences, interruptions, erreurs et ressources.

Pour une analyse ponctuelle de prononciation ou de qualite audio, activer `Inclure le texte lu dans les logs de diagnostic` depuis le menu de l'app. Le choix est persistant, mais ne s'applique qu'aux nouveaux evenements.

`Effacer les logs audio` supprime le journal JSONL et le journal local Voxtral. Utiliser cette commande apres un test contenant du texte sensible.

## Dictionnaire de prononciation

Le menu `Ouvrir le dictionnaire de prononciation` ouvre le CSV dans TextEdit, et non Numbers. Modifier uniquement les lignes sous l'entete `source,replacement`, avec une entree par ligne, puis enregistrer avec `Cmd+S` en conservant le format texte. Les commandes `Importer` et `Exporter` permettent de transferer les corrections personnelles entre deux Mac sans ecraser le dictionnaire d'un autre utilisateur.

## Transferer l'app

`./create-distribution.sh` produit une archive ZIP personnelle dans `Distribution/out`. Elle contient l'app, une notice et `Preparer Voxtral.command`.

- macOS TTS: decompresser, glisser l'app dans `/Applications`, puis autoriser la Surveillance de l'entree si macOS le demande.
- Voxtral Streaming: lancer une fois `Preparer Voxtral.command` avec une connexion internet. Il verifie Apple Silicon, prepare la version testee de `mlx-audio` et telecharge le modele local. `uv` doit etre installe au prealable.

L'archive convient a un transfert personnel. Pour une distribution a des collegues sans etape Gatekeeper manuelle, signer avec Developer ID puis notariser l'archive ou un futur DMG/PKG.
