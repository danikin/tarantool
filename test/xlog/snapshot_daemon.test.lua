fio = require 'fio'
errno = require 'errno'
fiber = require 'fiber'
env = require('test_run')
test_run = env.new()


PERIOD = 0.03
if jit.os ~= 'Linux' then PERIOD = 1.5 end


space = box.schema.space.create('snapshot_daemon')
index = space:create_index('pk', { type = 'tree', parts = { 1, 'num' }})


box.cfg{snapshot_period = PERIOD, snapshot_count = 2 }

no = 1
-- first xlog
for i = 1, box.cfg.rows_per_wal + 10 do space:insert { no } no = no + 1 end
-- second xlog
for i = 1, box.cfg.rows_per_wal + 10 do space:insert { no } no = no + 1 end
-- wait for last snapshot
fiber.sleep(1.5 * PERIOD)
-- third xlog
for i = 1, box.cfg.rows_per_wal + 10 do space:insert { no } no = no + 1 end
-- fourth xlog
for i = 1, box.cfg.rows_per_wal + 10 do space:insert { no } no = no + 1 end

-- wait for last snapshot

test_run:cmd("setopt delimiter ';'")

for i = 1, 100 do
    fiber.sleep(PERIOD)
    snaps = fio.glob(fio.pathjoin(box.cfg.snap_dir, '*.snap'))
    xlogs = fio.glob(fio.pathjoin(box.cfg.wal_dir, '*.xlog'))

    if #snaps == 2 then
        break
    end
end;

test_run:cmd("setopt delimiter ''");



#snaps == 2 or snaps
#xlogs > 0

fio.basename(snaps[1], '.snap') >= fio.basename(xlogs[1], '.xlog')

-- restore default options
box.cfg{snapshot_period = 3600 * 4, snapshot_count = 4 }
space:drop()

box.cfg{ snapshot_count = .2 }

daemon = box.internal.snapshot_daemon
-- stop daemon
box.cfg{ snapshot_period = 0 }
-- wait daemon to stop
while daemon.fiber ~= nil do fiber.sleep(0) end
daemon.fiber == nil
-- start daemon
box.cfg{ snapshot_period = 10 }
daemon.fiber ~= nil
-- reload configuration
box.cfg{ snapshot_period = 15, snapshot_count = 20 }
daemon.snapshot_period == 15
daemon.snapshot_count = 20

-- stop daemon
box.cfg{ snapshot_count = 0 }

-- first start daemon
box.cfg{ snapshot_count = 2, snapshot_period = 3600}
period_bias = daemon.snapshot_period_bias
next_snap_interval = daemon.next_snap_interval(daemon)
test_snap_interval = 3600 - (fiber.time() + period_bias) % 3600
(next_snap_interval - test_snap_interval + 3600) % 3600 < 2

biases = {}
max_equals = 0
test_run:cmd("setopt delimiter ';'")

for i = 1, 20 do
    box.cfg{ snapshot_period = 0}
    box.cfg{ snapshot_period = 3600}
    biases[daemon.snapshot_period_bias] = (biases[daemon.snapshot_period_bias] or 0) + 1
    if biases[daemon.snapshot_period_bias] > max_equals then
        max_equals = biases[daemon.snapshot_period_bias]
    end
end

test_run:cmd("setopt delimiter ''");
max_equals < 4
