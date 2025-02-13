# Dotfiles on Github

* [Rationale and Implementation](https://drewdevault.com/2019/12/30/dotfiles.html)
* [Repo](https://github.com/iot49/dotfiles)
    * **KEY:** `.gitignore` "*"

## Setup

```{bash}
cd ~
git init
git remote add origin https://github.com/iot49/dotfiles
git pull origin main
```

Use normal git commands. Do not forget **-f** with `git add`!

* `git add -f ...`
* `git push`
* `git pull`

## Ideas

* [Zero-Trust SSH with Cloudflare](https://runcloud.io/blog/zero-trust-ssh)