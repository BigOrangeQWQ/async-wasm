// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
suberror Err derive(Show)

///|
test "group defer basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.add_defer(() => log.write_string("first group defer\n"))
    root.spawn_bg(fn() {
      defer log.write_string("defer for first task\n")
      @async.pause()
      root.add_defer(() => log.write_string("third group defer\n"))
      @async.pause()
      log.write_string("first task finished\n")
    })
    root.spawn_bg(fn() {
      defer log.write_string("defer for second task\n")
      @async.pause()
      root.add_defer(() => log.write_string("second group defer\n"))
      @async.pause()
      log.write_string("second task finished\n")
    })
    root.spawn_bg(no_wait=true, fn() {
      defer log.write_string("defer for cancelled task\n")
      @async.pause()
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|defer for cancelled task
      #|first task finished
      #|defer for first task
      #|second task finished
      #|defer for second task
      #|second group defer
      #|third group defer
      #|first group defer
      #|
    ),
  )
}

///|
test "group defer error" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.add_defer(() => log.write_string("first group defer\n"))
      root.spawn_bg(fn() {
        defer log.write_string("defer for first task\n")
        @async.pause()
        root.add_defer(() => log.write_string("third group defer\n"))
        @async.pause()
        log.write_string("first task finished\n")
      })
      root.spawn_bg(fn() {
        defer log.write_string("defer for second task\n")
        @async.pause()
        root.add_defer(() => log.write_string("second group defer\n"))
        @async.pause()
        log.write_string("second task raise error\n")
        raise Err
      })
      root.spawn_bg(no_wait=true, fn() {
        defer log.write_string("defer for cancelled task\n")
        @async.pause()
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|defer for cancelled task
      #|first task finished
      #|defer for first task
      #|second task raise error
      #|defer for second task
      #|second group defer
      #|third group defer
      #|first group defer
      #|Err(Err)
    ),
  )
}
