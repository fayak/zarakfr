#!/usr/bin/env bash

set -xeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JEKYLL_IMAGE="${JEKYLL_IMAGE:-jekyll/jekyll:4.2.2}"

docker run --rm \
	--name blog-builder \
	-v "$ROOT_DIR/site:/srv/jekyll" \
	-v "$ROOT_DIR/bundle:/usr/local/bundle" \
	-e JEKYLL_ENV=production \
	-e BUNDLE_PATH=/usr/local/bundle \
	"$JEKYLL_IMAGE" /bin/bash -lc "chmod a+w /srv/jekyll/Gemfile.lock && chmod 777 /srv/jekyll && (bundle check || bundle install) && bundle exec jekyll build"

cp -r "$ROOT_DIR"/site/_site/* /srv/www/zarak.fr
