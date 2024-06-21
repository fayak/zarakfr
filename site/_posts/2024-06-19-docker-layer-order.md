---
layout: single
title:  "Maitriser l'ordre des instructions et layers dans votre Dockerfile"
date:   2024-06-19 15:00:00 +0200
author: "zarak"
excerpt: "Comprendre l'impact de l'ordre des instructions dans un Dockerfile"
description: "Améliorer ses images docker en comprenant certains mécanismes internes"
header:
    overlay_image: /resources/dockerfile.jpg
    overlay_filter: "0.5"
    caption: "Exemple de Dockerfile"
    show_overlay_excerpt: true
    teaser: /resources/dockerfile.jpg

categories:
    - devops

toc: true
toc_sticky: true
classes: wide
---

# Docker et les layers
## Explications très succincte des layers

Docker fonctionne grâce à Overlayfs* et des layers. Une image est composée de layers, assemblés au lancement d'un
container pour former le filesystem final.

\* Overlayfs dans la plupart des cas. Docker peut également utiliser d'autre engines, mais overlayfs est celui par défaut
et le plus répandu.
{: .notice--info }

Lors de la création d'une image, nous créons ces layers, et nous y ajoutons des métadonnées. Chaque instruction* d'un
Dockerfile ajoute un Layer, ou une métadonnées à l'image finale.

Prenons le Dockerfile suivant comme exemple :

{% highlight bash %}
FROM python:alpine

LABEL key=value
ENV key=value

RUN echo 1 > 1
RUN echo 2 > 2
RUN echo 3 > 3
{% endhighlight %}

Cette image possède au moins 4 layers :
- au moins 1 via `python:alpine`, image de base utilisée ici (en réalité probablement plus)
- 1 layer par instruction `RUN`

Les instructions ENV et LABEL ne génèrent pas de layers, mais uniquement des métadonnées
{: .notice--success }

On peut apercevoir ces layers avec les commandes docker push/pull qui indiquent quels layers sont pushed/pulled
{: .notice--info }

Pour réellement voir les layers, on utilisera la commande `docker inspect <id/name> | jq '.[0]'.RootFS.Layers`
{: .notice--success }

Plutôt que d'écrire 3 `RUN` différents ici, regroupons les en un pour économiser les layers :

{% highlight bash %}
FROM python:alpine

LABEL key=value
ENV key=value

RUN echo 1 > 1 && \
    echo 2 > 2 && \
    echo 3 > 3
{% endhighlight %}

## Pourquoi est-ce important ?

Plusieurs raisons :
- Plus on a de layers, moins notre image sera efficace (plus lente à push/pull, léger overhead au runtime, ...)
- L'image peut s'en retrouver plus lourde :

{% highlight bash %}
$ cat Dockerfile-cache
FROM python:3.12-alpine

RUN dd if=/dev/zero of=./file bs=100M count=1
RUN echo do something
RUN rm ./file

$ cat Dockerfile-no-cache
FROM python:3.12-alpine

RUN dd if=/dev/zero of=./file bs=100M count=1 && \
    echo do something && \
    rm ./file

$ docker build -t no-cache -f Dockerfile-no-cache .
[...]
$ docker build -t cache -f Dockerfile-cache .
[...]
$ docker image ls | grep cache
no-cache         latest            b7649a20b96b   30 seconds ago   57.5MB
cache            latest            9a36cf7702b2   30 seconds ago   162MB
{% endhighlight %}

- L'image peut leaker des secrets :
{% highlight bash %}
$ cat Dockerfile
FROM python:3.12-alpine

RUN echo "secret password" > /password
RUN echo do something with the file /password [...]
RUN rm /password

$ docker build -t password .
[...]

$ docker run --rm --entrypoint cat password /password
cat: can\'t open '/password': No such file or directory
$ # /password file seems to be removed from the image, yay !

$ cat $(docker inspect password | jq -r '.[0].GraphDriver.Data.LowerDir' | cut -d ':' -f2)/password"
secret password
$ # Actually isn't, still in the image
{% endhighlight %}

- Permet d'économiser de l'espace disque si les images partagent des layers (voir juste en dessous)
- Permet de build des images plus rapidement et efficacement (voir juste en dessous)

# Ordonnons les layers
## Pourquoi ordonner les layers ?

Ordonner ses layers a 2 énormes impacts pour tout le monde :

- Si 2 images différentes ont toutes les deux besoins de python 3.12 et d'avoir git, elles peuvent partager des layers.
Tous les layers partagés ne dupliquent pas l'espace disque pris. Ainsi, si deux images pour deux applications A et B,
basées sur python 3.12 et git, sont bien construite, l'espace disque sera de `sizeof(python 3.12 + git) + sizeof(A) + sizeof(B)`.

  Si elles sont mal construites, l'espace disque total sera au mieux de `sizeof(python 3.12) + 2*sizeof(git) + sizeof(A) + sizeof(B)`, et au pire
`2*sizeof(python 3.12) + 2*sizeof(git) + sizeof(A) + sizeof(B)`.
L'espace disques est donc significativement impacté, le temps de push/pull également, voire le startup time (si on doit pull l'image avant).

- Un développeur qui travaille sur une application avec son image va vouloir rebuild l'image fréquemment, pour tester.
  Il est fort probable que les dépendances de l'image évoluent rarement, que les dépendances de l'application évoluent
peu fréquemment et que l'application évoluent fréquemment.

  Si pour un changement minime de code, par exemple ajouter un commentaire, il faut re-télécharger toutes les dépendances, le temps
de build en devient catastrophiquement long et les serveurs des associations et volontaires qui hébergent les
dépendances se font contacter inutilement. En résulte un temps de build trop long, un développeur frustré, et de la bande
passante gâchée.

  Si au contraire les instructions du Dockerfile sont bien ordonnées, nous n'avons pas ce problème grâce à
la réutilisation du cache de build.

## Comment faire ?

La rule of thumb pour écrire son Dockerfile est de chercher à minimiser les layers. Mais il faut également garder en
tête le cache, et l'utiliser avec habileté.

Dans ce billet, on va prendre pour exemple la construction d'une image docker pour une
application en Python, image qui nécessite `git` et des dépendances pythons listées
dans un `pyproject.toml`.

Le contenu de l'application `app.py` et du `pyproject.toml` n'ont que peu d'importance ici.

Voici un Dockerfile naïf :
{% highlight bash %}
FROM python:3.12-alpine

WORKDIR /app
ENV POETRY_CACHE_DIR=/tmp/poetry_cache

COPY . .

RUN apk add git && \
    pip3 install poetry && \
    poetry install --only main --no-root && rm -rf $POETRY_CACHE_DIR

ENTRYPOINT ["python3", "/app/app.py"]
{% endhighlight %}

Un seul run qui regroupe donc plusieurs layers en un, pas de layer de cache supprimé par la suite qui traîne dans
l'image finale, sela semble intelligent en apparence.

Mais si on ajoute un commentaire basique dans le code de l'application, absolument toutes les dépendances python et git
seront réinstallées, et on perd environ mille ans.

Une meilleure manière de faire :
{% highlight bash %}
FROM python:3.12-alpine

WORKDIR /app
ENV POETRY_CACHE_DIR=/tmp/poetry_cache

RUN apk add git && pip3 install poetry

COPY pyproject.toml poetry.lock ./

RUN poetry install --only main --no-root && rm -rf $POETRY_CACHE_DIR

COPY app.py ./

ENTRYPOINT ["python3", "/app/app.py"]
{% endhighlight %}

Il y a ici plus de layers. Mais le changement le plus fréquent, celui du code source, n'entraîne que la re-copie du code
et non pas l'install des dépendances, grâce au cache du builder Docker. L'opération prend très peu de temps.

L'opération moins fréquente de changement des dépendances python ne provoque pas la réinstallation de git, uniquement
le `COPY pyproject.toml` (et la suite).

Et seul le changement le plus rare, celui des dépendances d'image/d'OS (git par exemple), entraîne le rebuild complet.

Si l'on possède 2 applications A et B qui dépendent toutes les deux de `python:3.12-alpine` et de `git`, si le début des
deux Dockerfile est identique, les deux images résultantes vont partager leurs premiers layers. Tout bénef !

# Multi stage build

Si l'on est amateur de multi stage build, et que l'on cherche à avoir un comportement similaire, il faut changer légèrement
les choses.

Voici un exemple :
{% highlight bash %}
FROM python:3.12-alpine as base

WORKDIR /app

RUN apk add git

FROM python:3.12-alpine as builder

ENV POETRY_CACHE_DIR=/tmp/poetry_cache

RUN pip3 install poetry

COPY pyproject.toml poetry.lock ./

RUN poetry install --only main --no-root && rm -rf $POETRY_CACHE_DIR

FROM base

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv

COPY app.py ./

ENTRYPOINT ["python3", "/app/app.py"]
{% endhighlight %}

L'exemple est plus complexe, mais permet d'utiliser efficacement le cache et les layers.
