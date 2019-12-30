sources of [zarak.fr](https://zarak.fr)

This website is built using Jekyll and Minimal Mistakes

How to run with docker :
```bash
$ mkdir bundle
$ docker run --rm \
    --name blog \
    -v `pwd`/site:/srv/jekyll \
    -v `pwd`/bundle:/usr/local/bundle \
    -p 4000:4000 --user root:root \
    jekyll/jekyll /bin/bash -c "jekyll server --trace"
```
