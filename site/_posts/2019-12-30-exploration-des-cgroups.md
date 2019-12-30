---
layout: single
title:  "Exploration et prise en main des cgroups"
date:   2019-12-30 00:00:00 +0200
author: "zarak"
excerpt: "Découverte et tour d'horizon des cgroups V1"
header:
    overlay_image: /resources/linux-cgroups.jpg
    overlay_filter: "0.5"
    caption: "Photo by [Shmuel Csaba Otto Traian](https://commons.wikimedia.org/wiki/File:Linux_kernel_unified_hierarchy_cgroups_and_systemd.svg?uselang=fr)"
    show_overlay_excerpt: true
    teaser: /resources/linux-cgroups-sm.jpg

categories:
    - linux

toc: true
toc_sticky: true

---

Cet article est en cours de rédaction
{: .notice--danger}

# Qu'est-ce que les cgroups ?

## A qui s'adresse cet article ?

Cet article s'adresse aux gens qui ont une connaissance relativement avancée
de Docker (ou autre technique de conteneurisation) en tant qu'utilisateur, mais
ne connaissent pas les mécanismes internes mis en oeuvre pour leur fonctionnement.
Plus en précisemment, pour ceux qui ne savent pas ce que sont (voire même n'ont
jamais entendu parler) des cgroups.

Il faut avoir une vague idée de comment le kernel linux fonctionne pour pouvoir
comprendre facilement cet article.

## Introduction

Le but de cet article est de fournir une petite introduction sommaire aux cgroups.
N'étant moi-même pas un expert de Docker ou du kernel Linux, mais un simple
amateur enthousiaste, j'ai récemment eu l'envie de découvrir un peu plus le
fonctionnement interne de Docker et des conteneurs, après plusieurs années à
utiliser Docker sans réellement comprendre ce qu'il se passe sous le capot.
Si les noms d'`overlayfs`, `cgroups`, `capabilities` et
`namespace` m'étaient familier, je n'avais cependant qu'une vague connaissance
de ces mécanismes. J'ai donc cherché à en savoir plus sur les cgroups, pour
répondre à quelques questions:
- Qu'est-ce que c'est ?
- A quoi ça sert ?
- A quoi ça sert pour Docker et les conteneurs ?
- Comment les manipuler ?

## Présentation brève (style wikipédia) des cgroups

Le terme `cgroups` signifie `control groups`. La documentation de Linux précise
qu'il existe la forme singulière, et que `cgroups` ne doit jamais être capitalisé.
En réalité, `cgroup` est une espèce de raccourci pour `cgroup controller`.

Cette fonctionnalité a été ajouté à Linux vers la fin 2007, pour la version 2.6.24.

Depuis la version 4.5 de linux, les cgroups existent également en version 2,
mais cet article n'en parlera pas.

Le but des cgroups est donc d'établir un groupe de process sur lequel on va
pouvoir excercer un contrôle via certaines règles et paramètres. Une des
fonctionnalité offerte par les cgroups est la possibilité d'organiser ces
groupes de process selon une hiérarchie.

Ainsi, un cgroup controller permet d'effectuer un contrôle sur un type de
ressource, par exemple le cgroup controller _memory_ permet de limiter
l'utilisation totale de RAM ou de swap pour les process dans ce cgroup.

Un process peut être dans plusieurs cgroups, pour être sous le joug de plusieurs
limites de différents types.

Le système hiérarchique des cgroups permet de limiter les ressources de
plusieurs cgroups d'un coup, un cgroup situé en aval d'un autre ne peut dépasser
les limites imposées par ce dernier.

# Un peu de concret

## man mount(8)

Les cgroups sont en réalité exposé via un filesystem particulier interne (de type ... `cgroup`).
Pour les manipuler (en créer, les modifier, rajouter des process, etc), il faut ainsi passer
par le filesystem.

Avec les OS récents disposants de systemd, ce dernier défini automatiquement
des points de montages et monte les pseudo-filesystems requis pour utiliser
tous les cgroups (de la version 1).

Ainsi, sur ma machine :

{% highlight bash %}

$ uname -a
Linux ... 5.2.5-arch1-1-ARCH #1
$ mount
[...]
cgroup on /sys/fs/cgroup/cpu,cpuacct type cgroup (rw,nosuid,nodev,noexec,relatime,cpu,cpuacct)
cgroup on /sys/fs/cgroup/hugetlb type cgroup (rw,nosuid,nodev,noexec,relatime,hugetlb)
cgroup on /sys/fs/cgroup/cpuset type cgroup (rw,nosuid,nodev,noexec,relatime,cpuset)
cgroup on /sys/fs/cgroup/freezer type cgroup (rw,nosuid,nodev,noexec,relatime,freezer)
cgroup on /sys/fs/cgroup/net_cls,net_prio type cgroup (rw,nosuid,nodev,noexec,relatime,net_cls,net_prio)
cgroup on /sys/fs/cgroup/devices type cgroup (rw,nosuid,nodev,noexec,relatime,devices)
cgroup on /sys/fs/cgroup/pids type cgroup (rw,nosuid,nodev,noexec,relatime,pids)
cgroup on /sys/fs/cgroup/perf_event type cgroup (rw,nosuid,nodev,noexec,relatime,perf_event)
cgroup on /sys/fs/cgroup/rdma type cgroup (rw,nosuid,nodev,noexec,relatime,rdma)
cgroup on /sys/fs/cgroup/memory type cgroup (rw,nosuid,nodev,noexec,relatime,memory)
cgroup on /sys/fs/cgroup/blkio type cgroup (rw,nosuid,nodev,noexec,relatime,blkio)
[...]

{% endhighlight %}

On note que `cgroup` ici est au singulier et non au pluriel. La documentation (`man 7 cgroups`) explique que le terme `cgroup` au singulier désigne le `control group controller`, là où le pluriel désigne la fonctionnalité dans son ensemble.
{: .notice--info}

On remarque que tous les cgroups montés sont chacun monté dans un dossier qui porte le nom de
l'option de montage du fs. Ainsi on a un `cgroup` dans le dossier `blkio` avec l'option de montage
`blkio`. Comme on peut le deviner assez facilement, c'est cette option de montage qui permet d'activer un cgroup controller.

Il est possible de préciser plusieurs options de montage avec la commande mount en les séparants par des virgules. Si l'on précise plsuieurs cgroup controllers lors du montage, alors on obtiendra un cgroup disposant de chacun de ces controllers. On remarque que systemd l'utilise dans le dossier `cpu,cpuacct` par exemple.
{: .notice--info}

## Créons notre cgroup

Maintenant qu'on a vu que pour intéragir avec un croup controller, il
suffit de monter dans un dossier un fs de type `cgroup` et d'activer le `cgroup controller`
qui nous intéresse via l'option de montage, essayons de créer et manipuler un cgroup.

Tentons d'utiliser le controller `memory` pour limiter la RAM d'un process :

{% highlight bash %}
$ cd /tmp
$ mkdir cgroup
$ mount -t cgroup -o memory cgroup cgroup
$ cd cgroup
cgroup.clone_children               memory.max_usage_in_bytes
cgroup.event_control                memory.memsw.failcnt
cgroup.procs                        memory.memsw.limit_in_bytes
cgroup.sane_behavior                memory.memsw.max_usage_in_bytes
docker/                             memory.memsw.usage_in_bytes
init.scope/                         memory.move_charge_at_immigrate
machine.slice/                      memory.numa_stat
memory.failcnt                      memory.oom_control
memory.force_empty                  memory.pressure_level
memory.kmem.failcnt                 memory.soft_limit_in_bytes
memory.kmem.limit_in_bytes          memory.stat
memory.kmem.max_usage_in_bytes      memory.swappiness
memory.kmem.slabinfo                memory.usage_in_bytes
memory.kmem.tcp.failcnt             memory.use_hierarchy
memory.kmem.tcp.limit_in_bytes      notify_on_release
memory.kmem.tcp.max_usage_in_bytes  release_agent
memory.kmem.tcp.usage_in_bytes      system.slice/
memory.kmem.usage_in_bytes          tasks
memory.limit_in_bytes               user.slice/
{% endhighlight %}

L'interface que nous propose le kernel pour intéragir avec un cgroup est donc
remplie de plusieurs fichiers. Si on les catégorise, on a:
- Ceux qui commencent par `memory`. Ce sont les interfaces propre au controller que l'on a activé.
- Ceux qui commencent par `cgroup`. Ce sont les interfaces communes à chacun des cgroups et qui permettent d'intéragir avec le groupe.
- 3 fichiers un peu à part, `notify_on_release`, `release_agent` et `tasks`. Les deux premiers sont des mécanismes de notification, et le troisième sera évoqué un peu plus bas dans cet article.
- Différents dossiers. Ce sont en réalité d'autre cgroups créé automatiquement par systemd et docker dans cet exemple.

