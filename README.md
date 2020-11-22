# FeedKit

The FeedKit Swift Package is a feed reading client specialized for podcast feeds. It implements searching, browsing, and caching feeds, as well as subscription management for a single user.

With FeedKit at its core, [Podest](https://github.com/michaelnisi/podest) is the most efficient podcast app.

## Services

FeedKit does not connect with feed providers or iTunes directly, instead it consumes JSON from two optimized REST APIs for browsing and searching.

- Browsing 🍡 [michaelnisi/manger-http](https://github.com/michaelnisi/manger-http)
- Searching 🐷 [michaelnisi/fanboy-http](https://github.com/michaelnisi/fanboy-http)

## Test

With **fanboy-http** and **manger-http** running locally (on ports 8383 and 8384), do:

```
$ swift test
```

## Install

📦 Add `https://github.com/michaelnisi/feedkit`  to your package manifest.

## License

[MIT License](https://github.com/michaelnisi/feedkit/blob/master/LICENSE)
