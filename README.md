# Dotfiles on Github

* [Rationale and Implementation](https://drewdevault.com/2019/12/30/dotfiles.html)
* [Repo](https://github.com/iot49/dotfiles)
    * **KEY:** `.gitignore` "*"
* [ZSH CheatSheet](https://gist.github.com/ClementNerma/1dd94cb0f1884b9c20d1ba0037bdcde2)

## Setup

```{bash}
cd ~
git init
git remote add origin https://github.com/iot49/dotfiles
git pull origin main
```

Use git as usual. Do not forget **-f** with `git add`!

* `git add -f ...`
* `git push`
* `git pull`

## Ideas

* [Zero-Trust SSH with Cloudflare](https://runcloud.io/blog/zero-trust-ssh)