# KickAlert

Addon World of Warcraft, multi-version (Classic Era, TBC, Wrath, Cata, MoP Classic, retail).
Version autonome de l'alerte Kick de MyBossSuite (`Modules/InterruptAlert`), avec un halo
d'écran en plus et un panneau d'options graphique.

Quand la cible ou le focus lance un sort interruptible **et** que ton interruption est
disponible (et à portée), trois alertes indépendantes se déclenchent :

- **Texte** : mot configurable (défaut `KICK`), police, taille, contour, couleur (color picker),
  pulsation réglable, position libre.
- **Halo** : bordure lumineuse sur les 4 côtés de l'écran, couleur et intensité (alpha via le
  color picker), épaisseur, pulsation réglable.
- **Son** : preset (`alarm`, `raidwarning`, `readycheck`, `ping`, `murloc`), id de SOUNDKIT ou
  fichier (`Interface\AddOns\X\kick.ogg`).

Chaque alerte s'active, se règle et se coupe séparément.

En plus de ces trois alertes centrées sur la cible/le focus, un mot **KICK** peut s'afficher
au-dessus de la nameplate de n'importe quelle cible hostile en train de lancer un sort
interruptible, sans avoir besoin de la cibler.

## Détection (reprise de MyBossSuite)

Trois conditions vérifiées ensemble, en continu pendant l'incantation :
cible (ou focus) en incantation, incantation non protégée (`notInterruptible`), ton interrupt
réellement disponible et à portée. Un ticker de 0,15 s tourne pendant l'incantation : un kick
qui revient de cooldown au milieu du cast n'est signalé par aucun event.

L'interrupt est détecté, pas configuré : table par classe filtrée par ce que le personnage connaît
vraiment (les rangs Classic sont couverts par le grimoire). `/ka spell <id>` force un cas non couvert.

Sur les clients où `UnitCastingInfo` ne répond rien sur une unité hostile, le combat log
(`SPELL_CAST_START`) prend le relais et le sort est supposé interruptible.

## Installation

Copier le dossier `KickAlert` dans `World of Warcraft/_<version>_/Interface/AddOns/`.
Un seul `KickAlert.toc`, sans suffixe de version : il est chargé par tous les clients,
et sa ligne `## Interface` liste les versions supportées (Classic Era, Anniversary,
Forever, TBC, Wrath, Cata, Mists, retail).

## Commandes

| Commande | Effet |
|---|---|
| `/ka` ou `/kickalert` | Ouvre le panneau d'options |
| `/ka unlock` / `/ka lock` | Affiche le texte en permanence et le rend déplaçable / verrouille |
| `/ka test` | Joue les 3 alertes pendant 3 secondes |
| `/ka reset` | Remet le texte à sa position par défaut |
| `/ka wipe` | Remet tous les réglages par défaut (SavedVariables et miroir CVar), puis recharge l'interface |
| `/ka spell <id>` / `/ka spell auto` | Force le sort d'interruption suivi / revient à la détection |
| `/ka status` | Interrupt détecté, disponibilité, options actives |
| `/ka sounds` | État de chaque son proposé sur ce client |
| `/ka sounds <motif>` | Cherche une constante SOUNDKIT, ex. `/ka sounds warning` |

Le texte et le halo restent affichés tant que le panneau d'options est ouvert : c'est l'aperçu.

## Langue

L'addon est en anglais à l'installation. Le panneau d'options propose les 11 langues
du client (plus « Auto » pour suivre celle du jeu) ; le changement s'applique au
rechargement de l'interface, via le bouton prévu à cet effet.

Une clé non traduite retombe sur l'anglais plutôt que de disparaître.

## Sons

Les constantes `SOUNDKIT` ne sont pas les mêmes d'un client à l'autre. Seuls les sons
que le client sait réellement jouer sont proposés — `/ka sounds` montre lesquels. Le
champ libre du panneau accepte en plus n'importe quel id `SOUNDKIT` ou chemin de
fichier (`Interface\AddOns\MonAddon\kick.ogg`).

## Fichiers

- `Compat.lua` : toutes les API qui diffèrent entre versions (sorts, incantations, portée, sons,
  timers, dégradés, color picker, panneau d'options). Copie de la partie utile de
  `MyBossSuite/Core/Compat.lua`.
- `Mirror.lua` : doubles des réglages pour WoW Forever 1.60, qui écrit les SavedVariables de compte mais ne les relit pas. La table est rangée dans `g_addonCategoriesCollapsed` (sauvegarde de Blizzard_AddOnList, `WTF/SavedVariables/`, relue au démarrage) et recopiée dans des CVars `KickAlertMirror1..8` (survivent au `/reload`). Si la sauvegarde revient vide, ces doubles la remplacent. Conséquence : supprimer `KickAlert.lua` dans `WTF` ne remet plus à zéro ; utiliser `/ka wipe`.
- `Core.lua` : SavedVariables (`KickAlertDB`), bus interne, mixin de positionnement, slash.
- `Alerts.lua` : les trois alertes.
- `Detector.lua` : port de `Modules/InterruptAlert/InterruptAlert.lua` sans la data WCL ni la
  rotation de groupe.
- `Nameplates.lua` : "KICK" au-dessus de la nameplate de toute cible hostile en incantation
  interruptible, sans ciblage.
- `Config.lua` : panneau d'options, widgets Blizzard uniquement.
- `tests/run.sh` : syntaxe + suite headless sur 4 configurations de client (`lua5.1` requis).

## Vérification

```bash
tests/run.sh
```

## Limites connues

- Classic Era ancien : sans `UNIT_SPELLCAST_*` sur la cible, seul le repli combat log fonctionne,
  et il ne sait pas si un sort est protégé.
- Le halo n'est pas déplaçable : il est lié aux bords de l'écran par construction.
- Polices supplémentaires uniquement via LibSharedMedia embarquée par une autre addon.

## Conformité avec la politique Blizzard sur les add-ons

Points de la *World of Warcraft UI Add-On Development Policy* et de la façon dont KickAlert les respecte :

| Exigence Blizzard | KickAlert |
|---|---|
| Add-on gratuit, aucun paiement ni fonctionnalité payante | Gratuit, licence GPL-3.0-or-later, aucune version premium |
| Code entièrement visible, ni caché ni obfusqué | Lua en clair, aucun `loadstring`, aucune chaîne encodée |
| Aucune publicité, aucune sollicitation de dons en jeu | Aucun message de ce type dans l'interface ni dans le chat |
| Aucune automatisation du jeu, aucun appel d'API protégée | L'addon **affiche** seulement : aucun `CastSpell*`, `TargetUnit`, `RunMacro`, `UseAction` ni action en combat. Le joueur lance lui-même son interruption |
| Pas d'impact négatif sur les royaumes ni les autres joueurs | Aucun message réseau (`SendAddonMessage`, chat), aucune requête externe ; le handler du combat log sort en deux comparaisons de chaînes |
| Aucun contenu offensant | Textes et sons choisis par le joueur, défauts neutres (`KICK`, sons du client) |
| Respect des CGU / EULA, Blizzard peut désactiver une fonctionnalité | Uniquement des API publiques documentées, passées par `Compat.lua` pour suivre les changements de client |

Données : uniquement les réglages du joueur dans `KickAlertDB` (SavedVariables). Aucune donnée
personnelle, aucune télémétrie.

World of Warcraft® et Blizzard Entertainment® sont des marques de Blizzard Entertainment, Inc.
KickAlert est un projet indépendant, ni affilié à ni approuvé par Blizzard Entertainment.

## Licence

GPL-3.0-or-later, comme MyBossSuite dont ce code dérive (voir `LICENSE`).
