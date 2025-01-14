# Bash Cache

Bash Cache provides a transparent mechanism for caching, or memoizing, long-running Bash functions.
Although it can be used for scripting its motivating purpose is to cache the results of expensive
commands for display in your terminal prompt.

Originally part of [ProfileGem](http://git.mwdiamond.com/profilegem) and
[prompt.gem](http://git.mwdiamond.com/prompt.gem), this functionality has been pulled out
into a standalone utility.

This library has also inspired [`bkt`](http://git.mwdiamond.com/bkt), a standalone binary for
caching subprocess invocations. If bash-cache doesn't fit your use case see if `bkt` does.

## Installation

Simply `source bash-cache.sh` into your script or shell.

## Usage

```
bc::cache FUNCTION TTL REFRESH [ENV_VARS ...]
```

To cache a function pass its name to `bc::cache`, along with the amount of time the cached results
should persist. This function [decorates](https://en.wikipedia.org/wiki/Decorator_pattern) an
existing Bash function, wrapping it with a caching layer that temporarily retains the output and
exit status of the backing function.

By default the cache is keyed off the function arguments (meaning `some_func`, `some_func bar`, and
`some_func baz` are each cached separately).

Cached data **is shared across processes** by default; see below for ways to change this.

Some example usages can be seen in the
[prompt.gem project](https://github.com/dimo414/prompt.gem/blob/master/env_functions.sh).

### Fidelity

There are many existing command-caching utilities and patterns in the wild, however the cached
behavior is typically incomplete (often only caching stdout). bash-cache strives to provide
high-fidelity caching, such that cached results are as close to indiscernable as possible.

* stdout and stderr are both cached, and output separately to stdout and stderr respectively
* output is lossless; many implementations can't handle trailing whitespace or `nul` bytes
* exit status code is preserved
* positional arguments are respected; naive implementations may conflate `foo bar baz` (two args)
  and `foo 'bar baz'` (one arg with whitespace)

### Cache durations

Each cached result is associated with two durations; the *TTL* deadline and the *refresh* deadline.
Durations can be specified in (s)econds, (m)inutes, (h)ours, and (d)ays, for example `30s`, `1d`,
or `1h24m5s`. 

* Once a cached result exceeds its TTL it is eligible for cleanup, and will shortly be removed.
  Note that until it is cleaned up the cached data may still be returned from the cache.
  `1m` is a recommended TTL duration for functions that will be surfaced in a prompt.
* If a cached result exceeds its refresh deadline it will be asynchronously updated when the
  function is invoked. The cached data will continue to be used until the refresh completes.
  `10s` is a recommended refresh duration for functions that will be surfaced in a prompt.

### Customizing the cache key

If your function depends on additional state, such as the current working directory, you'll want to
ensure the cache is keyed off that state, in addition to the function's arguments. To do so pass
any relevant environment variable names to `bc::cache` after the function name.

* `PWD` is often used in order to cache a function based on the current working directory.
* `$` is less common, but can be used to isolate a function's cache to the current process. Note
  you'll need to single-quote this argument (`'$'`).

### Example usage

You can invoke `bc::cache` at any time, however you're encouraged to do so immediately following
the function definition as a form of self-documentation, similar to
[Python's `@decorator` notation](https://en.wikipedia.org/wiki/Python_syntax_and_semantics#Decorators):

```shell
my_expensive_function() {
  ...
} && bc::cache my_expensive_function 1m 10s PWD
```

Notice in this example `PWD` is specified, meaning the cache will key off the current working
directory in addition to any arguments to the function.

### Performance

Cached data is stored on-disk, which means accessing the cache will typically be *much* slower than
directly executing many simple commands. Generally speaking, operations which benefit from caching
are accessing the disk themselves or doing network I/O. You should benchmark your functions with and
without caching (see `bc::benchmark`) to ensure you see a meaningful improvement before deciding to
cache a particular function.

Caching performance can differ drastically across machines. Notably, if the cache directory (under
`/tmp` or `TMPDIR` by default) is on a [`tmpfs`](https://en.wikipedia.org/wiki/Tmpfs) partition or a
solid-state drive performance will be significantly better than caching to a spinning disk.

### Calling the original function

If needed, the original function can be invoked via `bc::orig::FUNCTION_NAME` (e.g.
`bc::orig::my_expensive_function`).

### Warming the cache

If you anticipate a function will be called shortly you can warm the cache by calling
`bc::warm::FUNCTION_NAME`. This invokes the function in the background and caches its output.

### Cleanup

A cleanup task is run regularly to remove stale cache data, however no attempt is made to clean up
the cache directory on exit since by design the cache can be shared by multiple processes. By
default, cached data is stored in a temp directory that the OS will clean up from time to time
(generally on reboot), but if you override the cache directory via `BC_CACHE_DIR` you may want to
clean up the directory yourself.

**Note:** cached data is cleaned up asynchronously, therefore data may persist longer than the
specified TTL duration.

### Locking

By design the caching provided by bash-cache is racy - concurrent invocations may or may not end up
reusing the same cached value. For most cases (idempotent functions, to be precise) this should be
sufficient.

For cases where concurrent calls to the backing function are problematic, use `bc::locking_cache`
instead of `bc::cache`. This behaves identically to `bc::cache` but uses an advisory mutex lock to
prevent concurrent invocations of the backing function.

Note that needing mutual-exclusion is a **strong** signal that you should be using a more powerful
language than Bash, and that the locking bash-cache provides is
[advisory](https://en.wikipedia.org/wiki/File_locking#In_Unix-like_systems) and best-effort only.

## Other Functions

### `bc::benchmark`

Benchmarks a function without caching enabled, and with a cold and warm cache. This allows you to
see the overhead introduced by Bash Cache and decide if it's beneficial for your function.

This function runs in a subshell against a clean cache directory, and works for any function - you
do not need to have previously called `bc::cache`.

`bc::benchmark_memoize` provides the same basic benchmarking for `bc::memoize`.

### `bc::copy_function`

This helper function copies an existing function to a new name. This can be used to decorate or
replace a function by first copying the function and then defining a new function with the original
name. This is how `bc::cache` overwrites the function being decorated.

If desired you can stop caching a particular function by copying the `bc::orig::...` function back
to its original name:

```shell
bc::copy_function bc::orig::my_expensive_function my_expensive_function
```

### `bc::on` and `bc::off`

Enables or disables caching process-wide. If `bc::off` is called all cached functions will delegate
immediately to the original function they decorate and will not attempt to use cached data or
cache new data. Call `bc::on` to re-enable caching.

## Configuration

### Use an isolated cache directory

By default bash-cache stores cached output in a user-specific directory under `/tmp` or the path
specified by `TMPDIR`. To use a different path as the cache root set `BC_CACHE_DIR` before sourcing
`bash-cache.sh`. This is useful if you're using Bash Cache across multiple scripts, as you could
otherwise run into namespace collisions (e.g. two scripts caching different functions with the same
name).

## Copyright and License

Copyright 2012-2020 Michael Diamond

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
