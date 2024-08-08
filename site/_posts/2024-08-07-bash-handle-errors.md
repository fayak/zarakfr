---
layout: single
title:  "[EN] Bash error handling: the final guide"
date:   2024-08-07 15:00:00 +0200
author: "zarak"
excerpt: "Bash error handling is notoriously complex. Let's figure out how to have the best error handling"
description: "Getting into details on how to handle errors in bash"
header:
    overlay_image: /resources/bash-error.jpg
    overlay_filter: "0.5"
    caption: "Exemple de Dockerfile"
    show_overlay_excerpt: true
    teaser: /resources/bash-error.jpg

categories:
    - devops

toc: true
toc_sticky: true
classes: wide
---

# Level 0: no error handling

When writing a bash script, by default error are not handled:

{% highlight bash %}
#!/usr/bin/env bash
# main.sh

false  # is an error, return 1
echo "I'm still here !"
{% endhighlight %}

{% highlight bash %}
$ ./main.sh
I'm still here !
{% endhighlight %}

This behaviour creates mistakes and bugs, and not paying attention to bash error handling is one of the worst mistake
you can make while writing a bash script.

Why is that you ask ?

Let's consider this basic example:

{% highlight bash %}
#!/usr/bin/env bash
# main.sh

cd temporary-directory
rm -rf .
{% endhighlight %}

If the directory we want to remove `temporary-directory` doesn't exists, we instead remove (wrongfully) the current
directory instead of stopping the execution.

This example is of course very stupid and could also be avoided by simply writing `rm -rf temporary-directory` directly.
But think about how many times a command you execute could have desastrous effect on the next ones if it failed ?
{: .notice--info }

# Level 1: minimal error handling

To avoid the previous situation, the well known `set -e` can be used. It makes the script fail if any command fail.
Well, not quite, but more about that soon enough.

{% highlight bash %}
#!/usr/bin/env bash
# main.sh

set -e

false
echo "Not executed"
{% endhighlight %}

{% highlight bash %}
$ ./main.sh
$ echo $?
1
{% endhighlight %}

The behaviour is better. But we're still not stopping the script on some failures !

# Level 2: basic error handling

Let's consider this script with 2 of the next problems we'll face:

{% highlight bash %}
#!/usr/bin/env bash
# main.sh

set -e

user_to_remove="$1"
rm -rf /home/"$user_to_remove"

[...]

git_commit_short="$(git rev-parse HEAD | head -c 8)"

[...]
{% endhighlight %}

First, the script takes a parameter, the user to remove. But if the parameter is not provided, `$1` still defaults to
empty, causing the script to continue executing with the `$user_to_remove` variable empty.

To avoid this problem, simply use the `set -u` (`u` for `unset`) option. As per the manual:

Treat unset variables and parameters other than the special parameters ‘@’ or ‘\*’, or array variables subscripted with ‘@’ or ‘\*’, as an error when performing parameter expansion. An error message will be written to the standard error, and a non-interactive shell will exit.
{: .notice--info }

Secondly, we have a command substitution running 2 commands in a pipe, in a subshell. If the `git` command doesn't work,
because `git` is not installed, or because the current directory is not a git repository for example, the script
still continues executing.

This behaviour is surprising, but because `head -c 8` will succeed, bash will consider the whole pipeline as a success,
and despite the `set -e`, not stop the script here.

To avoid it, you can add the `set -o pipefail` option.

This is why on most scripts, blog post articles or stackoverflow responses you will see a `set -euo pipefail` at the
begginning of the script.

This is pretty good alreay, but will not cover error handling perfectly yet.

# Level 3: error tracing

When writing complex bash script or script meant to be run frequently, it might be desirable to have a [Sentry](https://sentry.io/welcome/)
integration, or at least a stack trace printed when a failure occurs. The stacktrace is very useful when working with
more batteries-included languages like Python, so let's try to mimic it.

<div>
A common option to debug a bash script includes the `set -x` option. It is a good start, often needed to understand
deeply a problem, but not very readable for multiple reasons:<br/>
- It only show the values, not the variable names, which is sometime confusing<br/>
- It's hard to understand pipes<br/>
- It's hard to understand nested functions<br/>
- It's very verbose and if loops are involved, finding the culprit call might be difficult<br/>
</div>
{: .notice--info }

Here's a script for stacktraces:

{% highlight bash %}
#!/usr/bin/env bash
# main.sh

set -eEuo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-.}" )" &> /dev/null && pwd )
function stacktrace() {
    cd "$SCRIPT_DIR"
    local i=1 line file func
    while read -r line func file < <(caller "$i"); do
        echo "[$i] $file:$line $func(): $(sed -n "$line"p "$file")" 1>&2
        i=$((i++))
    done
}

trap 'catch_err' ERR

function catch_err() {
    stacktrace
}

##########

function sub2() {
    false
}

function sub1() {
    sub2
}

sub1
{% endhighlight %}

A few things have changed in the script. Let's unwind after testing this new script:

{% highlight bash %}
$ ./main.sh
[1] ./main.sh:25 sub2():     false
[2] ./main.sh:29 sub1():     sub2
[3] ./main.sh:32 main(): sub1
{% endhighlight %}

Yay ! Stacktrace !

What changed ?

- We added `set -E` to propagate the `trap 'catch_err' ERR` in subshells that we defined later on
- We added this `trap` to call our function `catch_err` whenever an error that would cause the script to exit due to `set -e` is detected (aka, a non-zero return code)
- We defined this `catch_err` function which is simple for now, but we'll add some features later on
- And we defined the `stacktrace` function, needing `$SCRIPT_DIR` variable to properly read the source files, that will read the call stack and get the associated source code

To add the sentry integration we've mentionned, we can simply extend the `catch_err` function:

{% highlight bash %}
[...]

trap 'catch_err $?' ERR

function catch_err() {
    stacktrace_msg="$(stacktrace 2>&1)"
    send_sentry "$1" "$stacktrace_msg"
    1>&2 echo -e "$stacktrace_msg"
}

function send_sentry() {
    # Don't do anything if sentry-cli command doesn't exist
    if ! command -v sentry-cli &> /dev/null; then
        return
    fi

    local return_code="$1"
    local stacktrace_msg="$2"
    cd "$SCRIPT_DIR"
    local line file func
    read -r line func file < <(caller 1)
    error_line="$(sed -n "$line"p "$file" | awk '{$1=$1};1')"
    sentry-cli send-event \
        -m "$error_line: return code $return_code" \
        -a "$stacktrace_msg" \
        -t user_sudo:"${SUDO_USER:-${USER:-undefined}}" || echo Could not send sentry event 1>&2
}

[...]
{% endhighlight %}

We gained in complexity !

1. First, we also collect the return code of the command that lead to the error in our trap.
2. Then we add this `send_sentry` function, that will send to sentry using Sentry's official `sentry-cli` command - if
    it's available - some information. Information including the stacktrace, the error line with the return code, and we
    also added a `user_sudo` tag as an example here, to know who's the real user that used the script before `sudo`.

    Things to note here:
    - `sentry-cli` will need to be configured. One can simply define `$SENTRY_DSN` variable in the env at the beginning
        of the script
    - Tags can be added freely
    - `sentry-cli` will send the whole environment to the error trace, including some eventual secrets. If it's an issue,
        some environment variables needs to be explicitly overwritten when calling `sentry-cli`
3. The stacktrace is then directly printed to the user as well

# Level 4: Terminate everything cleanly

The state of error handling so far looks good. But it's not enough if the script is complex, has pipelines and creates
subprocesses and subshells everywhere.

For example :
{% highlight bash %}
$ tail -n 1 main.sh
sub1 | tee -a /dev/null
$ ./main.sh
Event dispatched: 43acc50a-5b8a-4c26-8a68-0b7795fd983a
[1] ./main.sh:45 sub2():     false
[2] ./main.sh:50 sub1():     sub2
[3] ./main.sh:53 main(): sub1 | tee -a /dev/null
Event dispatched: 371f6b05-d0b4-4224-b3d7-c4e9880f57d7
[1] ./main.sh:53 main(): sub1 | tee -a /dev/null
{% endhighlight %}

`sub1` creates the error, but it is reported twice, creating 2 stacktraces and 2 Sentry events. However, only one error
shall be reported, the `sub1` call.

On top of that, we want to kill all the processes that were spawned by our script, to not leave any leftovers.

And because the error can come from the main script, or a subshell, we have to handle all those cases as well.

Some people - including me - also like to use `set -x` to have some more verbosy debuggy output. Let's try to not
interfere with the debugging in our error-handling functions.

Oh and also, in many cases we have some cleanup to do after our script finishes. We could call a `cleanup` function at
the end of our main function, but in case of an error, or if `exit` is called earlier, this `cleanup` function won't be
called. So better use a bash trap, make sure that it's automatically done, and forget about it.

So let's add all these requirements and complexify the thing to its maximum !


{% highlight bash %}
#!/usr/bin/env bash

set -eTEuo pipefail

get_pgid() {
    cut -d " " -f 5 < "/proc/$$/stat" | tr ' ' '\n'
}

pgid="$(get_pgid)"
if [[ "$$" != "$pgid" ]]; then
    exec setsid "$(readlink -f "$0")" "$@"
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-.}" )" &> /dev/null && pwd )
function stacktrace() {
    cd "$SCRIPT_DIR"
    local i=1 line file func
    while read -r line func file < <(caller "$i"); do
        echo "[$i] $file:$line $func(): $(sed -n "$line"p "$file")" 1>&2
        i=$((i++))
    done
}

trap 'set +x; end 1' SIGUSR1 SIGTERM
trap 'set +x; end' EXIT
trap 'set +x; catch_err $?' ERR

function catch_err() {
    stacktrace_msg="$(stacktrace 2>&1)"
    send_sentry "$1" "$stacktrace_msg"
    1>&2 echo -e "$stacktrace_msg"

    if [[ "$$" == "$BASHPID" ]]; then
        end 1
    else
        PGID="$(get_pgid)"
        kill -10 -- "$PGID"
        sleep 1
        kill -15 -- "$PGID"
    fi
}

function cleanup() {
    rm -rf "${TMP_FILE:-}" || true  # FIXME
}

function end() {
    local return_code="${1:-}"
    trap '' EXIT
    set +e  # At this point, if things fail, we can't do much more
    [[ -z "$(jobs -p)" ]] || kill "$(jobs -p)" 2> /dev/null
    if [[ "$$" == "$BASHPID" ]]; then
        cleanup
    fi
    [[ -z "$return_code" ]] || exit "$return_code"
}


function send_sentry() {
    # Don't do anything if sentry-cli command doesn't exist
    if ! command -v sentry-cli &> /dev/null; then
        return
    fi

    local return_code="$1"
    local stacktrace_msg="$2"
    cd "$SCRIPT_DIR"
    local line file func
    read -r line func file < <(caller 1)
    error_line="$(sed -n "$line"p "$file" | awk '{$1=$1};1')"
    sentry-cli send-event -m "$error_line: return code $return_code" \
        -a "$stacktrace_msg" \
        -t user_sudo:"${SUDO_USER:-${USER:-undefined}}" || echo Could not send sentry event 1>&2
}

######

function sub2() {
    false
}

function sub1() {
    sleep 0.1
    sub2
}

TMP_FILE="$(mktemp)"

{ sleep 3 ; } &
echo "ok"
{ sub1 ; } &
echo "not ok"
wait
{% endhighlight %}


Let's analyze this code !

By the way, the code is far from being perfect. I've tested it in some situation and it seemed to fit my needs. If you
spot a corner case, or some misbehaviour, please let me know !
{: .notice--info }

Let's not start with the beginning of the script, but let's jump to the `catch_err` function and its additions.

Using `if [[ "$$" == "$BASHPID" ]]; then`, we can know if we are the parent process of the process tree we (may) have
created, and have a different behaviour.

<div>
It is common to think that $$ represents the current PID. This is often true, but sometimes incorrect. The man explicitely states:<br/>
<i>($$) Expands to the process ID of the shell. In a subshell, it expands to the process ID of the invoking shell, not the subshell. </i><br/>
`BASHPID` is the real PID of the process.
</div>
{: .notice--info }

If we are the main process, we call the `end` function directly. Otherwise, we send a `SIGUSR1` signal to the main process.

Thanks to the new traps established (`trap 'end 1' SIGUSR1 SIGTERM`), the `SIGUSR1` signal will call the `end` function.
If the main process is stuck, waiting for another command to end, we force the termination ourselves by sending a `SIGTERM`
to all the processes in the process group.

In bash, when waiting for a command to finish synchronously (aka simply running `command` and not running it in the
background and waiting for it to finishes with `wait`), signals are not interrupting the script and are queued. Well,
one instance of each different signals received are queued in the order they arrived. It means that if bash is waiting
for a command that never finishes (or takes too much times for us), it will never be interrupted. Only SIGKILL is the
exception, for obvious reasons.
{: .notice--info }

In both cases, the main process lands in the `end` function we added, reponsible for .. well, for the end of the script.

`end` takes an optionnal parameter, the return code the whole script shall return in the end. When called from a signal
SIGUSR1 or SIGTERM, or called by `catch_err`, the return_code will be `1`.

The `end` function is also called on regular script exiting thanks to the `trap 'end' EXIT` trap. In this case, no
`return_code` argument is provided to the `end` function, causing the function to not explicitely exit itself, because
it would overwrite the desired exit code.

This `end` function sends a SIGTERM to all the processes spawned by the script, trying to not leave any processes behind.

If the `end` function is called from the main process, we call the `cleanup` function. This ensures the cleanup function
is run only once.

But let's get back to a few lines above, where we came up with a process group ID, and killed the whole process group.

When running a bash script, it may or may not create its own process group, depending on how it was called. If you
started it from the terminal, by running `./main.sh`, `main.sh` when started by bash will create a new process group,
and by default each new process started in this process group will be part of it, like a subshell, or most commands.

If the script is started by another bash script (not in interactive mode), in python by `subprocess.run` without the
`start_new_session=True` option, etc, the script will not have its own process group.

We want our main process to have its own, to be sure that we can kill all the processes it creates in case of an error,
to avoid leaving ever-living processes.

So, to be sure that we already have our own process group, the very first thing we want to do is to check if we have it,
otherwise, we re-execute ourself the same way but with a new process group thanks to `setsid`.


# Conclusion

This snippet can probably be included in any big bash script project, and I would recommend doing so.
However, please note that while I have tested quite some use cases, it's far from being perfect and may cause troubles.
If you notice anything wrong or broken, add a comment on the [github snippet](https://gist.github.com/fayak/866e37739ad11ee43c2f34495b2358f3)
