## Freechains-Liferea GUI

Freechains is a decentralized topic-based publish-subscribe system:

https://github.com/Freechains/jvm

Liferea is an RSS reader which we adapted to Freechains:

https://github.com/Freechains/liferea

## Install

```
$ sudo apt-get install liferea lua5.3 lua-json lua-socket pandoc zenity
$ cd <to-this-repository-directory>
$ sudo make install
```

## Setup

- Start Freechains at `localhost:8330`.

- Open `liferea`.

- Delete default feeds:

```
Example Feeds -> Delete
```

- Intercept links in posts:

```
Tools -> Preferences -> Browser -> Browser -> Manual -> Manual ->
    freechains-liferea %s
```

In some versions, clicking a link still opens the browser.
Alternativelly, use the command line:

```
$ gsettings set net.sf.liferea browser 'freechains-liferea %s'
```

- Add the `/` chain:

```
+ New Subscription -> Advanced -> Command -> Source
    freechains-liferea freechains://localhost:8330//?cmd=atom
```

- Enable automatic refreshing:
```
Tools -> Preferences -> Feeds -> Refresh Interval ->
    5 minutes
```

- Click on the `/` feed and then on the `Menu` headline to start using it!
