---
layout: single
title:  "Exploration et prise en main des cgroups"
date:   2019-12-30 00:00:00 +0200
author: "zarak"
excerpt: "Découverte et tour d'horizon des cgroups V1"
description: "Les cgroups sont un mécanisme de Linux au coeur de Docker et des technologies de conteneurisation. Il peut être pertinent de s'y intéresser et comprendre à quoi ils servent, et comment les manipuler."
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

### Préparons le terrain

Maintenant qu'on a vu que pour intéragir avec un croup controller, il
suffit de monter dans un dossier un fs de type `cgroup` et d'activer le `cgroup controller`
qui nous intéresse via l'option de montage, essayons de créer et manipuler un cgroup.

Tentons d'utiliser le controller `memory` pour limiter la RAM d'un process :

Ces commandes sont faites en root
{: .notice--info}

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

### Constatation immédiate

On peut déjà remarquer que même si nous venons de créer notre dossier dans `/tmp`,
et qu'on vient à peine de mount le cgroup memory, il y a déjà des cgroups fils
(`docker`, `system.slice`, `user.slice`, etc) qui sont présents.
La raison est assez simple : les cgroups sont uniques au système.
Mount un cgroup quelque part permet juste d'intéragir avec ce système, qui est unique.
Ainsi, Docker et Systemd ont pu déjà créer leurs cgroups au démarrage de ma machine,
et utilisant la même interface mais mount ailleurs (`/sys/fs/cgroup/memory` en l'occurence, comme vu plus haut).

### La création

La création en elle-même est triviale :

{% highlight bash %}
$ mkdir myapp
{% endhighlight %}

Grâce à un simple `mkdir`, nous venons de créer un groupe appelé `myapp` de type
`memory`.

### Configuration de notre cgroup et ajout de process

Pour utiliser le cgroups, on va premièrement le configurer brièvement :

{% highlight bash %}
$ cd myapp
$ ls
cgroup.clone_children               memory.memsw.failcnt
cgroup.event_control                memory.memsw.limit_in_bytes
cgroup.procs                        memory.memsw.max_usage_in_bytes
memory.failcnt                      memory.memsw.usage_in_bytes
memory.force_empty                  memory.move_charge_at_immigrate
memory.kmem.failcnt                 memory.numa_stat
memory.kmem.limit_in_bytes          memory.oom_control
memory.kmem.max_usage_in_bytes      memory.pressure_level
memory.kmem.slabinfo                memory.soft_limit_in_bytes
memory.kmem.tcp.failcnt             memory.stat
memory.kmem.tcp.limit_in_bytes      memory.swappiness
memory.kmem.tcp.max_usage_in_bytes  memory.usage_in_bytes
memory.kmem.tcp.usage_in_bytes      memory.use_hierarchy
memory.kmem.usage_in_bytes          notify_on_release
memory.limit_in_bytes               tasks
memory.max_usage_in_bytes
$ echo "104857600" > memory.limit_in_bytes  # 100Kib
$ cat memory.limit_in_bytes
104857600
{% endhighlight %}

En écrivant la valeur 104857600 dans le fichier `memory.limit_in_bytes`, on
configure ce cgroup pour qu'il empêche la somme de la mémoire utilisée par les
process rattachés à lui-même de dépasser 100Kib.

Ajoutons notre shell courant à ce cgroup :

{% highlight bash %}
$ cat cgroup.procs
$ echo 0 > cgroup.procs
$ cat cgroup.procs
173423
173493
{% endhighlight %}

En écrivant 0 dans `cgroups.procs` on demande au kernel de déplacer le process
actuel (donc mon shell) dans ce cgroup. L'opération revient à `echo $$ > cgroups.procs`.

On vérifie ensuite quels sont les process qui sont dans ce cgroups avec un cat,
et on tombe bien sur deux valeurs, le PID de mon shell, et le PID de `cat` que je viens
d'invoquer. En effet, comme `cat` est mon process fils, il est par défaut dans le même
cgroup que moi-même. Refaire un autre `cat` nous donneras également "173423" mais le deuxième
PID sera différent.

### Test du cgroup

Maintenant que nous sommes dans un cgroup, et que celui ci nous impose une limite
de RAM de 100Kib, essayons de voir ce qu'il se passe quand on la brise.

Dans un autre shell (important !), je prépare un petit code en C que je vais compiler :

{% highlight C %}
#include <stdlib.h>
#include <unistd.h>

int main(void)
{
    char str[] = "Memory exhausted";
    while (1)
    {
        void *ptr = malloc(1024*1024); /* Allocate all the memory */
        if (ptr == NULL) /* Memory exhausted */
        {
            write(2, str, sizeof(str)); /* Write the error message
                (using write to avoid internal printf memory allocation) */
            while (1)
                continue;
        }
    }
    return 0;
}
{% endhighlight %}

Ce script a pour but d'allouer plein de mémoire jusqu'à ce qu'il n'y en ai plus de disponible,
puis de print un message d'erreur et d'attendre de se faire tuer.

{% highlight bash %}
$ gcc -O0 /tmp/test.c -o /tmp/test
{% endhighlight %}

Lancons le programme avec notre shell soumis au cgroup `myapp` :

{% highlight bash %}
$ /tmp/test
[1]    173722 killed     /tmp/test
$ /tmp/test
[1]    173795 killed     /tmp/test
{% endhighlight %}

Notre process semble se faire tuer avant de pouvoir print ou de rentrer dans
sa boucle infini.

Quelqu'un d'un peu familier avec le fonctionnement de linux va immédiatement
suspecter l'OOM-killer d'être passé par là :

{% highlight bash %}
$ dmesg
[170370.111087] test invoked oom-killer: gfp_mask=0x400dc0(GFP_KERNEL_ACCOUNT|__GFP_ZERO), order=0, oom_score_adj=0
[170370.111090] CPU: 1 PID: 174205 Comm: test Tainted: G        W         5.4.3-arch1-1 #1
[170370.111091] Call Trace:
[170370.111098]  dump_stack+0x66/0x90
[170370.111101]  dump_header+0x4a/0x1f7
[170370.111103]  oom_kill_process.cold+0xb/0x10
[170370.111104]  out_of_memory+0x197/0x440
[170370.111107]  mem_cgroup_out_of_memory+0xba/0xd0
[170370.111109]  try_charge+0x80b/0x880
[170370.111112]  __memcg_kmem_charge_memcg+0x46/0xd0
[170370.111113]  __memcg_kmem_charge+0x7d/0x1a0
[170370.111115]  __alloc_pages_nodemask+0x258/0x320
[170370.111118]  pte_alloc_one+0x14/0x40
[170370.111120]  __pte_alloc+0x18/0x120
[170370.111122]  __handle_mm_fault+0x12b9/0x14a0
[170370.111124]  handle_mm_fault+0xce/0x200
[170370.111126]  do_user_addr_fault+0x1ef/0x470
[170370.111128]  page_fault+0x34/0x40
[170370.111130] RIP: 0033:0x7feee527cae2
[170370.111132] Code: ff ff ff b9 22 00 00 00 ba 03 00 00 00 4c 89 e6 e8 53 15 07 00 48 83 f8 ff 74 c3 4c 8d 40 10 a8 0f 0f 85 17 05 00 00 4c 89 e2 <48> c7 00 00 00 00 00 48 83 ca 02 48 89 50 08 ba 01 00 00 00 f0 0f
[170370.111132] RSP: 002b:00007ffd4002d8f0 EFLAGS: 00010246
[170370.111133] RAX: 00007fe312b8a000 RBX: 00007feee53b49e0 RCX: 00007feee52ee046
[170370.111134] RDX: 0000000000101000 RSI: 0000000000101000 RDI: 0000000000000000
[170370.111135] RBP: 0000000000100010 R08: 00007fe312b8a010 R09: 0000000000000000
[170370.111135] R10: 0000000000000022 R11: 0000000000000246 R12: 0000000000101000
[170370.111136] R13: 0000000000001000 R14: 0000000000010001 R15: 000000000000ffff
[170370.111138] memory: usage 102400kB, limit 102400kB, failcnt 457756
[170370.111139] memory+swap: usage 295612kB, limit 9007199254740988kB, failcnt 0
[170370.111139] kmem: usage 101976kB, limit 9007199254740988kB, failcnt 0
[170370.111140] Memory cgroup stats for /myapp:
[170370.111148] anon 421888
                file 0
                kernel_stack 36864
                slab 4198400
                sock 0
                shmem 0
                file_mapped 405504
                file_dirty 0
                file_writeback 270336
                anon_thp 0
                inactive_anon 368640
                active_anon 569344
                inactive_file 409600
                active_file 0
                unevictable 0
                slab_reclaimable 974848
                slab_unreclaimable 3223552
                pgfault 1463748
                pgmajfault 1023
                workingset_refault 0
                workingset_activate 0
                workingset_nodereclaim 0
                pgrefill 1414155
                pgscan 2831737
                pgsteal 1401281
                pgactivate 1419
                pgdeactivate 1414155
                pglazyfree 0
                pglazyfreed 0
                thp_fault_alloc 0
                thp_collapse_alloc 0
[170370.111148] Tasks state (memory values in pages):
[170370.111149] [  pid  ]   uid  tgid total_vm      rss pgtables_bytes swapents oom_score_adj name
[170370.111151] [ 173423]     0 173423     2906     1768    57344      123             0 zsh
[170370.111152] [ 174205]     0 174205 12396714      329 99405824    48209             0 test
[170370.111153] oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),cpuset=/,mems_allowed=0,oom_memcg=/myapp,task_memcg=/myapp,task=test,pid=174205,uid=0
[170370.111159] Memory cgroup out of memory: Killed process 174205 (test) total-vm:49586856kB, anon-rss:152kB, file-rss:1156kB, shmem-rss:8kB, UID:0 pgtables:99405824kB oom_score_adj:0
[170370.130845] oom_reaper: reaped process 174205 (test), now anon-rss:0kB, file-rss:0kB, shmem-rss:0kB
{% endhighlight %}

En effet, notre programme s'est fait tuer avant de pouvoir print quoi que ce soit.

En regardant rapidement dans notre cgroup, on découvre le fichier `memory.oom_control`.
Écrivons "1" dedans pour désactiver l'OOM killer pour ce cgroup, et retentons notre
expérience :

{% highlight bash %}
$ echo 1 > memory.oom_control
$ /tmp/test

{% endhighlight %}

Le programme tourne à l'infini, mais n'affiche rien. De plus, mon CPU n'est pas
en train de cramer. Explorons un peu dans un autre shell :

{% highlight bash %}
$ ps aux | grep test
root      174337  0.9  0.0 49615640 1068 pts/8   D+   15:28   0:00 /tmp/test
{% endhighlight %}

Le `D+` sur la ligne du process indique que celui-ci est en état uninterruptable
sleep (D), et au premier plan d'un process group (+). En regardant dans la documentation
du kernel, on peut effectivement lire :

```
You can disable the OOM-killer by writing "1" to memory.oom_control file, as:

 #echo 1 > memory.oom_control

If OOM-killer is disabled, tasks under cgroup will hang/sleep
in memory cgroup's OOM-waitqueue when they request accountable memory.

For running them, you have to relax the memory cgroup's OOM status by
 * enlarge limit or reduce usage.
To reduce usage,
 * kill some tasks.
 * move some tasks to other group with account migration.
 * remove some files (on tmpfs?)

Then, stopped tasks will work again.
```

Le comportement actuel est donc celui attendu, notre process a épuisé la
mémoire disponible et est donc bloqué.

# Conclusion

Les cgroups sont en réalité assez facile à comprendre et manipuler grâce à leur
interface assez simple. Cependant, derrière cette apparente simplicité se cache
beaucoup de complexité dans le kernel, et quelques incohérences (certains articles
sur internet expliquerons mieux que moi pourquoi).

Ces mécanismes sont néanmoins à la base du fonctionnement d'outils de conteneurisation
que l'on connait et utilise régulièrement aujourd'hui.

Il existe une volonté de faire bouger les cgroups vers une nouvelle interface,
avec un fonctionnement assez différent, les cgroups v2, qui feront surement
l'objet d'un nouvel article de blog.
