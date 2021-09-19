#!/usr/bin/env bash

set -xe

docker run --rm \
	--name blog-builder \
	-v $(pwd)/site:/srv/jekyll \
	-v $(pwd)/bundle:/usr/local/bundle \
	-e JEKYLL_ENV=production \
	jekyll/jekyll /bin/bash -c "chmod a+w /srv/jekyll/Gemfile.lock && chmod 777 /srv/jekyll && jekyll build"

cp -r site/_site/* /srv/www/zarak.fr
