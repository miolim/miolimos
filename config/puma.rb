# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# #578 (Hans-Go, 2026-06-11): Cluster-Modus — mehrere Worker-Prozesse,
# damit parallele schwere Requests (Markdown-Rendering ist CPU-bound)
# sich nicht gegenseitig blockieren. Maschine hat 8 Kerne / 16 GB.
# preload_app! teilt den App-Code via CoW zwischen den Workern.
workers ENV.fetch("WEB_CONCURRENCY", 4)
preload_app!

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
#
# NOTE: do not add a bind address here (`port ENV.fetch("PORT", 3000), host`).
# When the server is started through `rails server`, Rails passes its own bind
# address to Puma and silently overrides whatever this file sets — the change
# looks clean and does nothing. Verified 2026-07-21 on the sibling instances:
# both kept listening on 0.0.0.0 after the config was changed, and only `-b`
# on the command line took effect.
#
# That matters for more than tidiness. This app is meant to sit behind a
# tunnel or reverse proxy, so production should bind the loopback interface
# and nothing else; a stray 0.0.0.0 exposes it to every host on the local
# network (and to any mesh VPN the machine happens to be part of). Set it
# where the process is started, e.g. in the systemd unit:
#
#   ExecStart=... bundle exec rails server -e production -b 127.0.0.1 -p 3007
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
