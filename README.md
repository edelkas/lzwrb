**WIP**

# lzwrb

lzwrb is a Ruby gem for LZW encoding and decoding. Main features:

* Pure Ruby, no dependencies.
* Highly configurable (constant/variable code length, bit packing order...). See [Configuration](#configuration).
* Compatible with many LZW specifications, including GIF (see [Presets](#presets)).
* Reasonably fast for pure Ruby (see [Benchmarks](#benchmarks)).

## Table of contents

- [What's LZW?](#what's-lzw)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Configuration](#configuration)
  - [Presets](#presets)
  - [Code length](#code-length)
  - [Packing order](#packing-order)
  - [Clear & Stop codes](#clear--stop-codes)
  - [Custom alphabets](#custom-alphabets)
  - [Verbosity](#verbosity)
- [Benchmarks](#benchmarks)
- [Todo](#todo)
- [Notes](#notes)

## What's LZW?

In short, LZW is a dictionary-based lossless compression algorithm. The encoder scans the data sequentially, building a table of patterns and substituting them in the data by their corresponding code. The decoder, configured with the same settings, will recognize the same patterns and generate the same table, thus being able to recover the original data from the sequence of codes.

The original algorithm used constant code lengths (typically 12 bits), but this is wasteful, specially for data that can be represented with significantly fewer bits, thus variable code length was introduced. Another common feature is the usage of special _Clear_ and _Stop_ codes: When the table is full, the encoder and decoder have to reinitialize it, but this can also be done at will using the Clear code. Likewise, the Stop code indicates the end of the data, which may actually be necessary to avoid ambiguity (see [Clear & Stop codes](#clear--stop-codes)). See [Configuration](#configuration) for a more in-depth description of these and other features, and refer to the [Wikipedia article](https://en.wikipedia.org/wiki/Lempel%E2%80%93Ziv%E2%80%93Welch) for a more thorough explanation.

Nowadays, LZW has largely been replaced by other algorithms that provide a better compression ratio, notably [Deflate](https://en.wikipedia.org/wiki/Deflate), implemented by the ubiquitous [zlib](https://en.wikipedia.org/wiki/Zlib) and formats like Zip or GZip, and used in a plethora of file formats, like PNG images. Deflate also provides a faster decoding speed, though encoding is usually slower. Nevertheless, LZW still has its place in more classic formats yet in use, like GIF and TIFF images, PDF files, or the classic UNIX compress utility.

## Installation
_(This section is not accurate yet, since the tool hasn't been packaged into a gem yet, so it needs to be installed via cloning the repo)_

The setup procedure is completely standard.

### Using Bundler

With [Bundler](https://bundler.io/#getting-started) just add the following line to your Gemfile:

```ruby
gem 'lzw'
```
And then install via `bundle install`.

### Using RubyGems

With Ruby's package manager, just execute the following command on the terminal:
```
gem install lzw
```

You many need admin privileges (e.g. `sudo` in Linux). Beware of using sudo if you're using a version manager, like [RVM](https://rvm.io/) or [rbenv](https://github.com/rbenv/rbenv).

## Basic Usage
_(This section is not accurate yet, since the tool hasn't been packaged into a gem yet, so it needs to be used via cloning the repo first)_

Require the gem, create an `LZW` object with the desired settings and run the `encode` and `decode` methods.

The following example uses the default configuration, see the next section for a list of all the available settings, which can be provided to the constructor via keyword arguments.

```ruby
require 'lzw'
lzw = LZW.new
data = ...
cmp = lzw.encode(data)
res = lzw.decode(cmp)
puts res == data
```

Output sample:
```
Test
```
Note: The output can be reduced or suppressed (or detailed), see [Verbosity](#verbosity).

## Configuration

Most of the usual options for the LZW algorithm can be configured individually by supplying the appropriate keyword arguments in the constructor. Additionally, there are several presets available, i.e. a selection of setting values with a specific purpose (e.g. best compression, fastest encoding, compatible with GIF...). For example:

```ruby
lzw1 = LZW.new(preset: :gif)
lzw2 = LZW.new(min_bits: 8, max_bits: 16)
```

Individual settings may be used together with a preset, in which case the individual setting takes preference over the value that may be set by the preset, thus enabling the fine-tuning of a specific preset.

The following options are available:

Argument | Type | Description
--- | --- | ---
`:preset` | Symbol | Specifies which preset (set of options) to use. See [Presets](#presets).
`:bits` | Integer | Code length in bits, for constant length mode. See [Code length](#code-length).
`:min_bits` | Integer | Minimum code length in bits, for variable length mode. See [Code length](#code-length).
`:max_bits` | Integer | Maximum code length in bits, for variable length mode. See [Code length](#code-length).
`:clear` | Boolean | Whether to use Clear codes or not. See [Clear & Stop codes](#clear--stop-codes).
`:stop` | Boolean | Whether to use Stop codes or not. See [Clear & Stop codes](#clear--stop-codes).
`:lsb` | Boolean | Whether to use LSB or MSB (least/most significant bit packing order). See [Packing order](#packing-order).
`:alphabet` | Array | List of characters that compose the data to encode. See [Custom alphabets](#custom-alphabets).
`:verbosity` | Symbol | Specifies the amount of detail to print to the console. See [Verbosity](#verbosity).

### Presets

The following presets are currently available:

Preset | Description
--- | ---
`:best` | Aimed at best compression, uses variable code length (8-16 bits), no special codes and LSB packing
`:fast` | Aimed at fastest encoding, uses a constant code length of 16 bits, no special codes and LSB packing
`:gif` | This is the exact specification implemented by the GIF format, uses variable code length (8-12 bits), clear and stop codes, and LSB packing

### Code length

### Packing order

### Clear & Stop codes

### Custom alphabets

### Verbosity

### Others

## Benchmarks

## Todo

Eventually I'd like to have the following extra features tested and implemented:

### Main features

* Most significant bit (MSB) packing order.
* "Early change" support.
* Support for TIFF and PDF (requires the 2 features above).
* Support for UNIX compress (has a bug).

### Smaller additions

* Option to disable automatic table reinitialization.
* Deferred clear codes (for full GIF decoding support, hardly ever used).
* Choice between plain and rich logs.

### Optimizations

* Native packing for codes of constant width of 8, 16, 32 or 64 bits for extra speed.
* Use a Trie instead of a Hash for the encoding process.

### Development

* Add docs.
* Add changelog.
* Add Rake tests.
* Package as gem.

## Notes

* **Concurrency**: The `LZW` objects are _not_ thread safe. If you want to encode/decode in parallel, you must create a separate object for each thread, even if they use the same exact configuration.
* **Custom alphabets**: If you change the default alphabet (binary), ensure the data to be encoded can be expressed solely with that alphabet, or alternatively, specify the `safe` option to the encoder.