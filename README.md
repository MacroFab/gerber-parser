# gerber parser
[![Travis](https://img.shields.io/travis/mcous/gerber-parser.svg?style=flat-square)](https://travis-ci.org/mcous/gerber-parser)
[![Coveralls](https://img.shields.io/coveralls/mcous/gerber-parser.svg?style=flat-square)](https://coveralls.io/github/mcous/gerber-parser)
[![David](https://img.shields.io/david/mcous/gerber-parser.svg?style=flat-square)](https://david-dm.org/mcous/gerber-parser)
[![David](https://img.shields.io/david/dev/mcous/gerber-parser.svg?style=flat-square)](https://david-dm.org/mcous/gerber-parser#info=devDependencies)

**Work in progress.**

A printed circuit board Gerber and drill file parser. Implemented as a Node transform stream that takes a Gerber text stream and emits objects to be consumed by some sort of PCB plotter.

## how to

This module is written in ES2016, and thus requires iojs/Node >= v3.0.0. To run in the browser, it should be transpiled to ES5 with a tool like [Babel](https://babeljs.io/) and bundled with a tool like [browserify](http://browserify.org/) or [webpack](http://webpack.github.io/).

`$ npm install gerber-parser`

``` javascript
var fs = require('fs')
var GerberParser = require('gerber-parser')

var gerberParser = new GerberParser()
gerberParser.on('warning', function(w) {
  console.warn(w.message)
})

fs.createReadStream('/path/to/gerber/file.gbr', {encoding: 'utf8'})
  .pipe(gerberParser)
  .on('data', function(obj) {
    console.log(obj)
  })
```

## developing and contributing

The code is written in ES2015 to run in "modern" versions of Node. Tests are written in [Mocha](http://mochajs.org/) and run in Node, [PhantomJS](http://phantomjs.org/), and a variety of browsers with [Zuul](https://github.com/defunctzombie/zuul) and [Open Sauce](https://saucelabs.com/opensauce/). All PRs should be accompanied by unit tests, with ideally one feature / bugfix per PR. Code linting happens with [ESLint](http://eslint.org/) automatically pre-test and pre-commit.

Code is deployed on tags via [TravisCI](https://travis-ci.org/) and code coverage is tracked with [Coveralls](https://coveralls.io/).

### build scripts

* `$ npm run lint` - lints code
* `$ npm run test` - runs Node unit tests
* `$ npm run test-watch` - runs unit tests and re-runs on changes
* `$ npm run browser-test` - runs tests in a local browser
* `$ npm run browser-test-phantom` - runs tests in PhantomJS
* `$ npm run browser-test-sauce` - runs tests in Sauce Labs on multiple browsers
  * Sauce Labs account required
* `$ npm run ci` - Script for CI server to run
  * Runs `npm test` and sends coverage report to Coveralls
  * If you want to run this locally, you'll need to set some environment variables