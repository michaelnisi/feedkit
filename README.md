# FeedKit

The FeedKit framework provides feeds and entries. It implements searching, browsing, and caching feeds, as well as subscription management for a single user.

FeedKit sits at the core of the [Podest](https://github.com/michaelnisi/podest) podcast app.

## Dependencies

- [kean/Nuke](https://github.com/kean/Nuke), A powerful image loading and caching system
- [michaelnisi/fanboy-kit](https://github.com/michaelnisi/fanboy-kit), Search podcasts via proxy
- [michaelnisi/manger-kit](https://github.com/michaelnisi/manger-kit), Request podcasts via proxy
- [michaelnisi/ola](https://github.com/michaelnisi/ola), Check reachability
- [michaelnisi/skull](https://github.com/michaelnisi/skull), Swift SQLite
- [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing), 📸 Delightful Swift snapshot testing

## Services

- [michaelnisi/fanboy-http](https://github.com/michaelnisi/fanboy-http), Search podcasts
- [michaelnisi/manger-http](https://github.com/michaelnisi/manger-http), Browse podcasts

## Documentation

Want to know more? 📚 Browse the [docs](https://michaelnisi.github.io/feedkit/).

## Installation

Add the FeedKit framework and its dependencies to your Xcode workspace.

## Testing

Most tests expect to find [fanboy-http](https://github.com/michaelnisi/fanboy-http) and [manger-http](https://github.com/michaelnisi/manger-http) locally.

## License

[MIT License](https://github.com/michaelnisi/feedkit/blob/master/LICENSE)
