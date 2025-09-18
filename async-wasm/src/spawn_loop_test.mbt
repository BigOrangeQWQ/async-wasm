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
test "spawn_loop basic" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(fn() {
        log.write_string("tick \{i}\n")
        i = i + 1
        if i < 3 {
          IterContinue
        } else {
          IterEnd
        }
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|tick 0
      #|tick 1
      #|tick 2
      #|Ok(())
    ),
  )
}

///|
test "spawn_loop basic-error" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(fn() {
        log.write_string("tick \{i}\n")
        i = i + 1
        if i >= 3 {
          raise Err
        }
        IterContinue
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|tick 0
      #|tick 1
      #|tick 2
      #|Err(Err)
    ),
  )
}

///|
test "spawn_loop retry-immediate" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(retry=Immediate, fn() {
        log.write_string("tick \{i}\n")
        i = i + 1
        if i < 3 {
          raise Err
        }
        IterEnd
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|tick 0
      #|tick 1
      #|tick 2
      #|Ok(())
    ),
  )
}

///|
test "spawn_loop cancelled1" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(no_wait=true, allow_failure=true, retry=Immediate, fn() {
        @async.pause()
        log.write_string("loop \{i}\n")
        i = i + 1
        IterContinue
      })
      @async.pause()
    }),
  )
  inspect(log.to_string(), content="Ok(())")
}
