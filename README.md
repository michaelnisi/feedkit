# FeedKit

The FeedKit framework provides feeds and entries. It implements searching, browsing, and caching feeds, as well as subscription management for a single user.

FeedKit sits at the core of the [Podest](https://github.com/michaelnisi/podest) podcast app.

## Services

- [michaelnisi/fanboy-http](https://github.com/michaelnisi/fanboy-http), Search podcasts
- [michaelnisi/manger-http](https://github.com/michaelnisi/manger-http), Browse podcasts

## Test

With **fanboy-http** and **manger-http** running, do:

```
$ swift test
```

## Install

Add `https://github.com/michaelnisi/feedkit`  to your package manifest.

## License

[MIT License](https://github.com/michaelnisi/feedkit/blob/master/LICENSE)
