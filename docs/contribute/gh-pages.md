---
template: default
title: "GitHub Pages"
---
These instruction are only to make alterations to Jekyll templates, configuration, etc..., not to create documents. The documents are created and maintained within other branches as standard work practices dictates.

The docs/ folder is merged from the main branch when required. 

## Setup development tools

```bash
# https://github.com/rbenv/rbenv-installer
# https://github.com/rbenv/rbenv
# https://pages.github.com/versions/

curl -fsSL https://github.com/rbenv/rbenv-installer/raw/master/bin/rbenv-installer | bash
cat <<'EOT' >>"${HOME}/.profile"
# set PATH so it includes user's rbenv if it exists
if [ -d "$HOME/.rbenv/bin" ] ; then
    PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init -)"
fi
EOT

# Configure current shell
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

curl -fsSL https://github.com/rbenv/rbenv-installer/raw/master/bin/rbenv-doctor | bash

git clone https://github.com/rbenv/rbenv-default-gems.git $(rbenv root)/plugins/rbenv-default-gems
cat <<'EOT' >>$(rbenv root)/default-gems
bundler
EOT

sudo apt-get -y install \
  libssl-dev
rbenv install 2.7.1
rbenv global 2.7.1

bundle install
```

## Clone GitHub Pages branch

```bash
git clone -b gh-pages git@github.com:Australian-Imaging-Service/charts.git charts-docs
cd charts-docs
```

## Install dependancies for local rendering

```bash
bundle install
```

## Run a Jekyll server to render the site

```bash
bundle exec jekyll serve
```

## Merge docs/ folder from teh main branch if required

This should not be required as this process is a part of a GitHub Workflow when documentation is updated or added to the main branch.

```bash
git checkout main docs/*
git add .
git commit -m 'Merge docs folder from main branch'
git push
```
