---
layout: single
title:  "Systemd Before= After= Wants= RequiredBy= demystified"
date:   2023-01-16 19:00:00 +0200
author: "zarak"
excerpt: "Comprendre la relation entre unités systemd"
description: "Comprendre comment lier les unités systemd, avec .target"
header:
    overlay_image: /resources/systemd-dark.jpg
    overlay_filter: "0.5"
    caption: "Logo de systemd"
    show_overlay_excerpt: true
    teaser: /resources/systemd-dark.jpg

categories:
    - sre

toc: true
toc_sticky: true
classes: wide
---

# Comprendre par l'exemple les différents moyens de relier les unités systemd

## Setup de test

Pour les premier tests, nous allons considérer deux unités, `a.service` et `b.service`

Le but va être de considérer les différentes relations que l'on peut établir
entre `a` et `b` avec systemd, en essayant de conserver une approche où `a > b`.

Pour cela, on va essayer de lancer un script bash de test, qui a pour seul but
de voir les différents cas, notamment si un service fail ou pas. Voici le script
utilisé pour les `.service` :

{% highlight bash %}
#!/usr/bin/env bash

set -e

date
sleep 2
while $1; do
    sleep 10
    echo in loop @$(date)
done
$1
{% endhighlight %}

Le but ici est de pouvoir appelé le script avec un argument `true`/`false` pour
déclencher la boucle ou non.
La date et les `sleeps` servent pour comparer l'ordre de lancement (synchrone ou
asynchrone).

# Dépendances avec Wants=, Requires=, Requisite=, BindsTo= et PartOf=

Les tests de relation entre `a` et `b` sera fait avec les unités suivantes :

{% highlight toml %}
[Unit]
Description=a.service

[Service]
ExecStart=/tmp/service.sh true
{% endhighlight %}

{% highlight toml %}
[Unit]
Description=b.service
Wants=a.service

[Service]
ExecStart=/tmp/service.sh true
{% endhighlight %}

L'argument `true`/`false` de `service.sh` dans `ExecStart=` sera amené à changer
pour les différents tests (reflété dans le tableau par les colonnes 2 et 3),
et les propriétés de l'`[Unit]` de `b` également (première colonne).

Nous obtenons le tableau suivant :

| Mode                     | *a* success | *b* success || *a* started if *b* starts | *b* started if *a* starts | *a* stopped if *b* stops | *b* stopped if *a* stops | *b* fails                         | *b* dependency fail        |
|--------------------------|-------------|-------------||--------------------------:|--------------------------:|-------------------------:|-------------------------:|----------------------------------:|---------------------------:|
| Wants=                   | -           | True        || Yes                       | No                        | No                       | No                       | No                                | No                         |
| Wants=                   | -           | False       || Yes                       | No                        | No                       | No                       | Yes                               | No                         |
| Requires=                | False       | True        || Yes                       | No                        | No                       | Yes                      | No                                | Yes                        |
| Requires=                | False       | False       || Yes                       | No                        | No                       | Yes                      | Yes                               | /                          |
| Requires=                | True        | True        || Yes                       | No                        | No                       | Yes                      | No                                | No                         |
| Requires=                | True        | False       || Yes                       | No                        | No                       | Yes                      | Yes                               | No                         |
| Requires= + After= *\*1* | False       | -           || Yes                       | No                        | /                        | /                        | Yes                               | /                          |
| Requisite=               | True        | -           || No                        | No                        | No                       | Yes                      | if *a* not already started        | if *a* not already started |
| Requisite=               | False       | -           || No                        | No                        | /                        | /                        | Yes                               | Yes                        |
| BindsTo=                 | False       | True        || Yes                       | No                        | /                        | /                        | Yes                               | Yes                        |
| BindsTo=                 | False       | False       || Yes                       | No                        | /                        | /                        | Yes                               | Yes                        |
| BindsTo=                 | True        | False       || Yes                       | No                        | /                        | /                        | Yes                               | No                         |
| BindsTo=                 | True        | True        || Yes                       | No                        | No                       | Yes *\*2*                | No                                | No                         |
| PartOf=                  | -           | True        || No                        | No                        | No                       | Yes *\*3*                | *(3)*                             | No                         |
| PartOf=                  | -           | False       || No                        | No                        | No                       | Yes *\*3*                | *(3)*                             | No                         |

1. Pour effectivement avoir ce comportement, l'unité `a` doit avoir fail avant
   que `b` ne chercher à démarrer
2. Liaison encore plus forte qu'avec `Requires=`, puisque `b` va être stoppé peu
   importe la raison pour laquelle `a` devient inactif (pas uniquement `systemctl stop`)
3. Fonctionne aussi pour les restart

- Un `/` signifie que le cas n'est pas applicable.
- Un `-` indique que la valeur n'importe pas pour les résultats de la ligne
{: .notice--info }

# Relation de temps avec After= et Before=

Deux unités systemd reliées entre elle peuvent créer une dépendance de démarrage.
Dans ce cas, démarrer l'unité `b` va démarrer l'unité `a`. Cependant, par défaut,
les deux unité vont être démarrées "simultanément". Si l'on souhaite avoir une
ascendance de l'une sur l'autre, il faudra utiliser les propriétés `Before=`
et `After=` (dont elles sont elles-même leur opposé, cf la troisième section)

Partons du principe que `a.service` et `b.service` prennent 5s à démarrer, et qu'ils
ne vont pas fail. On a établi une relation de `b` vers `a` avec `b` possèdant un
`Wants=a.service` de tel sorte que l'activation de `b` active `a`.
Le comportement observé est donc très logique :

| *a* Before= | *a* After= | *b* Before= | *a* After= | Starting unit | *a* start time   | *b* start time     |
|-------------|------------|-------------|------------|---------------|-----------------:|-------------------:|
|             |            |             |            | `b`           | T0               | T0                 |
|             |            | a.service   |            | `b`           | T5               | T0                 |
|             |            |             | a.service  | `b`           | T0               | T5                 |
|             | b.service  |             |            | `a`           | T0               | - (no deps a -> b) |
|             | b.service  |             |            | `b`           | T5               | T0                 |
| b.service   |            |             |            | `b`           | T0               | T5                 |
|             |            | a.service   | a.service  | `b`           | - (config error) | T0                 |
|             | b.service  | a.service   |            | `b`           | T5               | T0                 |

Les autres cas sont assez évident à inférer.

On observe donc :

- Le comportement de démarrage asynchrone désiré quand la configuration est correcte
- Pas de liaison directe entre les unités avec uniquement `Before=`/`After=`.
  Une déclaraison de dépendance avec l'une des options de la première section est nécessaire.
- Les cas contradictoires sont traités comme tel et génèrent une erreur. Il est
  cependant intéressant de noter que l'erreur n'est déclenchée qu'à l'execution et
  n'est pas détectée à la création de l'unité.

# Sens des propriétés

Les propriétés testées ici sont testées en "forward" mode, c'est à dire que l'unité "fille" (`b`) déclare ses dépendances sur l'unité parent (`a`).
Il est possible de fonctionner en reverse mode, où le parent déclare une dépendance sur une unité fille en utilisant les alias reverse.

Voici la table de correspondance :

| Forward    | Reverse       | Section (forward)   | Section (reverse) |
|------------|---------------|---------------------|-------------------|
| Before=    | After=        | [Unit]              | [Unit]            |
| After=     | Before=       | [Unit]              | [Unit]            |
| Requires=  | RequiredBy=   | [Unit]              | [Install]         |
| Wants=     | WantedBy=     | [Unit]              | [Install]         |
| PartOf=    | ConsistsOf=   | [Unit]              | *Automatic*       |
| BindsTo=   | BoundBy=      | [Unit]              | *Automatic*       |
| Requisite= | RequisiteOf=  | [Unit]              | *Automatic*       |
| Triggers=  | TriggeredBy=  | *Automatic*         | *Automatic*       |
| Conflicts= | ConflictedBy= | [Unit]              | *Automatic*       |

Les propritétés flagguées en *Automatic* ne peuvent être spécifiées directement.

# Les .target

Les .target de systemd sont un moyen assez simple et abstrait de relier les unités
entre elles. On peut se représenter une .target comme un .service sans service
associé (??). L'idée est de se servir des .target comme point de controle, comme
point de synchronisation, pour gérer le flow d'execution de nos unités.

Les .target sont principalement utilisées pour la séquence de boot. Plutôt que
de définir les dépendances entre les .service directement entre eux sans
forcément connaitre explicitement le nom des services, on va pouvoir utiliser
les .target pour les lier par la fonctionnalité.

Si par exemple, je dispose de deux services `a` et `b`, mais que `a` n'a pas
"connaissance" que `b` est installé (car le role de `b` pourrait être géré par
un service `c`, `d`, ... L'administrateur a choisi `b` mais ce n'est pas une
obligation).

Le service `a` a besoin du service `b` car `b` s'occupe de mount les disques,
et `a` ne doit surtout pas se lancer tant que les disques ne sont pas mount.

Pour résoudre ce problème avec systemd, on pourrait être tenté de rajouter à `a`
une configuration du genre :
{% highlight TOML %}
[Unit]
After=b.service
Requires=b.service
{% endhighlight %}

Mais pour cela, il faut "connaitre" `b.service`. Le problème peut être résolu
autrement, et de manière moins coupleuse avec la configuration suivante :

{% highlight TOML %}
[Unit]
After=local-fs.target
Requires=local-fs.target
{% endhighlight %}

pour le service `a`, et :

{% highlight TOML %}
[Unit]
After=local-fs-pre.target
Before=local-fs.target
Wants=local-fs.target
{% endhighlight %}

Sont référencés ainsi 2 targets :
- `local-fs.target` va servir de point de contrôle pour regrouper les services
   qui s'occupent de mettre à disposition le filesystem local.
- `local-fs-pre.target` va servir de point de contrôle pour s'assurer que tous
   les services qui doivent s'executer avant la mise à disposition du filesystem
   local (via `local-fs.target` et les services qui référencent potentiellement cette target)
   se soient executés.

On peut voir la dépendance entre `local-fs.target` et `local-fs-pre.target` en
inspectant `local-fs.target`. On découvre ainsi `After=local-fs-pre.target`
{: .notice--info }

`b` qui se sait responsable (d'une partie) du job de mettre à disposition le
filesystem local va donc définir une dépendance sur cette target, et indiquer
qu'il doit d'executer avant cette target (pour ainsi valider la target).

`a` qui a besoin du filesystem local va également s'interfacer sur la `remote-fs.target`,
cette fois-ci dans l'autre sens. `a` ainsi n'a donc pas besoin de savoir qui
s'occupe de fournir le filesystem local (si c'est `b` ou un autre service), il
se concentre sur le besoin.

Un administrateur pourra donc interchanger `b` par `c` par la suite sans avoir
à changer `a` pour indiquer désormais `c` au lieu de `b` comme la première solution
le suggérait.

## Les target de boot par défaut

Un tour sur la man page de systemd Bootup nous propose le schéma suivant très
utile pour mieux visualiser :

<pre style="font-size: 12px;">
                             cryptsetup-pre.target veritysetup-pre.target
                                                  |
(various low-level                                v
 API VFS mounts:             (various cryptsetup/veritysetup devices...)
 mqueue, configfs,                                |    |
 debugfs, ...)                                    v    |
 |                                  cryptsetup.target  |
 |  (various swap                                 |    |    remote-fs-pre.target
 |   devices...)                                  |    |     |        |
 |    |                                           |    |     |        v
 |    v                       local-fs-pre.target |    |     |  (network file systems)
 |  swap.target                       |           |    v     v                 |
 |    |                               v           |  remote-cryptsetup.target  |
 |    |  (various low-level  (various mounts and  |  remote-veritysetup.target |
 |    |   services: udevd,    fsck services...)   |             |              |
 |    |   tmpfiles, random            |           |             |    remote-fs.target
 |    |   seed, sysctl, ...)          v           |             |              |
 |    |      |                 local-fs.target    |             | _____________/
 |    |      |                        |           |             |/
 \____|______|_______________   ______|___________/             |
                             \ /                                |
                              v                                 |
                       sysinit.target                           |
                              |                                 |
       ______________________/|\_____________________           |
      /              |        |      |               \          |
      |              |        |      |               |          |
      v              v        |      v               |          |
 (various       (various      |  (various            |          |
  timers...)      paths...)   |   sockets...)        |          |
      |              |        |      |               |          |
      v              v        |      v               |          |
timers.target  paths.target   |  sockets.target      |          |
      |              |        |      |               v          |
      v              \_______ | _____/         rescue.service   |
                             \|/                     |          |
                              v                      v          |
                          basic.target         rescue.target    |
                              |                                 |
                      ________v____________________             |
                     /              |              \            |
                     |              |              |            |
                     v              v              v            |
                 display-    (various system   (various system  |
             manager.service     services        services)      |
                     |         required for        |            |
                     |        graphical UIs)       v            v
                     |              |            multi-user.target
emergency.service    |              |              |
        |            \_____________ | _____________/
        v                          \|/
emergency.target                    v
                              graphical.target
</pre>
