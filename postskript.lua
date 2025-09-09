--
--
--
--
--
--
-- postskript
-- ...
-- v1.1 / imminent gloom 
-- 
-- primitive sampler
-- 
-- arc required!
-- 
-- controls, norns:
-- K2 - hold to record
-- K3 - clear
-- 
-- controls, arc:
-- E1 - rate
-- E2 - level
-- E3 - start
-- E4 - length
-- K1 - hold to record
--
-- personal:
-- E1 - bpm
-- E2 - crow cv 2
-- E3 - crow cv 3 & 4
--
-- no sound?
-- check softcut levels

-- setup
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

tab = require("tabutil")

local save_on_exit = false

a = arc.connect()

local s = screen
local fps = 120

local recording = false
local stopped = true
local press_time = 320
local prev_press_time = press_time
local active_buffer = 1
local recording_voice = 1
local playing_voice = 2
local loop_start = 0
local loop_length = 320
local loop_end = 320
local playback_position = 1
local max_length = 320
local max_level = 0
local level = 1
local rate = 1

local waveform = {}

-- params
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
params:add_group("postskript", "postskript", 7)

params:add_control("rate", "rate", controlspec.new(1/32, 1, 0.001, 0.001, 1))
params:set_action("rate",
   function(x)
      rate = x
      softcut.rate(playing_voice, x)
   end
)

params:add_control("level", "level", controlspec.new(0, 2.0, 0.001, 0.001, 1))
params:set_action("level",
   function(x)
      level = x
      softcut.level(playing_voice, x)
   end
)

params:add_control("start", "start", controlspec.new(0, 1, 0.001, 0.001, 0))
params:set_action("start",
   function(x)
      loop_start = press_time * x
      loop_end = util.clamp(loop_start + loop_length, 0.001, press_time)
      softcut.loop_start(playing_voice, loop_start)
      softcut.loop_end(playing_voice, loop_end)      
   end
)

params:add_control("length", "length", controlspec.new(0.001, 1, 0.001, 0.001, 1))
params:set_action("length",
   function(x)
      loop_length = press_time * x
      loop_start = util.clamp(loop_start, 0.001, loop_start)
      loop_end = util.clamp(loop_start + loop_length, 0.001, press_time)
      softcut.loop_start(playing_voice, loop_start)
      softcut.loop_end(playing_voice, loop_end)
   end
)

params:add_control("cv_1", "cv_1", controlspec.new(-5, 5, 0.001, 0.001, 0))
params:set_action("cv_1",
   function(x)
      crow.output[2].volts = x
   end
)

params:add_control("cv_2", "cv_2", controlspec.new(-5, 5, 0.001, 0.001, 0))
params:set_action("cv_2",
   function(x)
      crow.output[3].volts = x
   end
)

params:add_control("cv_3", "cv_3", controlspec.new(0, 10, 0.001, 0.001, 0))
params:set_action("cv_3",
   function(x)
      crow.output[4].volts = x
   end
)

-- functions
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local function record()
   recording = true
   stopped = false
   prev_press_time = press_time
   press_time = 0
   clk_press_timer:start()

   softcut.buffer_clear_channel(active_buffer)
   softcut.buffer(recording_voice, active_buffer)
   softcut.position(recording_voice, 0)
   softcut.position(playing_voice, 0)
   softcut.loop_start(recording_voice, 0)
   softcut.loop_end(recording_voice, 320)
   softcut.rec(recording_voice, 1)
end

local function play()
   recording = false
   clk_press_timer:stop()

   softcut.rec(recording_voice, 0)
   softcut.position(recording_voice, 0)
   softcut.position(playing_voice, 0)
   softcut.loop_start(recording_voice, 0)
   softcut.loop_end(recording_voice, press_time)
   softcut.play(recording_voice, 1)
   softcut.play(playing_voice, 0)

   softcut.render_buffer(active_buffer, 0, press_time, 64)

   params:set("rate", 1)
   params:set("level", 1)
   params:set("start", 0)
   params:set("length", 1)
   if active_buffer == 1 then
      active_buffer = 2
      recording_voice = 2
      playing_voice = 1
   else
      active_buffer = 1
      recording_voice = 1
      playing_voice = 2
   end        
end

local function clear()
   stopped = true
   softcut.play(1, 0)
   softcut.play(2, 0)
   softcut.position(1, 0)
   softcut.position(2, 0)
   softcut.buffer_clear()
   params:set("rate", 1)
   params:set("level", 1)
   params:set("start", 0)
   params:set("length", 1)
   for n = 1, 64 do waveform[n] = 0 end
end

local function on_render(ch, start, i, s)
   waveform = s
   for n = 1, 32 do
      table.insert(waveform, 1, waveform[#waveform])
      table.remove(waveform, #waveform)
   end
end

local function on_position(i, pos)
   playback_position = pos
end

-- modified from Arc:segment()
local function arc_segment(ring, from, to, level)
   local tau = math.pi * 2

   local function overlap(a, b, c, d)
      if a > b then
         return overlap(a, tau, c, d) + overlap(0, b, c, d)
      elseif c > d then
         return overlap(a, b, c, tau) + overlap(a, b, 0, d)
      else
         return math.max(0, math.min(b, d) - math.max(a, c))
      end
   end

   local function overlap_segments(a, b, c, d)
      a = a % tau
      b = b % tau
      c = c % tau
      d = d % tau

      return overlap(a, b, c, d)
   end

   local m = {}
   local sl = tau / 64

   for i=1, 64 do
      local sa = tau / 64 * (i - 1)
      local sb = tau / 64 * i

      local o = overlap_segments(math.rad(from), math.rad(to), sa, sb) -- added math.rad()
      m[i] = util.round(o / sl * level)
      if m[i] > 0 then -- skip updates if zero so we can draw over other things
         a:led(ring, i, m[i])
      end
   end
end

-- clock events
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function ui_event_arc()
   while true do
      clock.sleep(1/fps)
      arc_redraw()
   end
end

function ui_event_screen()
   while true do
      clock.sleep(1/fps/4)
      redraw()
   end
end

function delayed_init_event()
   clock.sleep(2)
   params:set("gridkeys_nb_voice", 17)
   -- params:set("sidv_nb_player", 17)
   nb:add_player_params()
end

function press_timer_event()
   if press_time < max_length then
      press_time = press_time + 0.001 -- seconds
   end
end

-- init
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function init()
   clk_ui_arc = clock.run(ui_event_arc)
   clk_ui_screen = clock.run(ui_event_screen)
   -- clk_delayed_init = clock.run(delayed_init_event)

   clk_press_timer = metro.init()
   clk_press_timer.event = press_timer_event
   clk_press_timer.time = 0.001

   for n = 2, 4 do
      crow.output[n].slew = 0.1
   end

   for n = 1, 2 do
      softcut.enable(n, 1)
      softcut.rate(n, 1)
      softcut.loop(n, 1)
      softcut.loop_start(n, 0)
      softcut.loop_end(n, 320)
      softcut.level(n, 1)
      softcut.rec_level(n, 1)
      softcut.pre_level(n, 0)
      softcut.pan(n, 0)
      softcut.level_slew_time(n, 0.0)
      softcut.recpre_slew_time(n, 0.0)
      softcut.fade_time(n, 0.01)
      softcut.level_input_cut(n, 1, 0.5)
      softcut.level_input_cut(n, 1, 0.5)
      softcut.level_input_cut(n, 2, 0.5)
      softcut.level_input_cut(n, 2, 0.5)
      softcut.pre_filter_dry(n, 1)
      softcut.pre_filter_lp(n, 0)
      softcut.pre_filter_bp(n, 0)
      softcut.pre_filter_hp(n, 0)
      softcut.post_filter_dry(n, 1)
      softcut.post_filter_lp(n, 0)
      softcut.post_filter_bp(n, 0)
      softcut.post_filter_hp(n, 0)
   end

   for n = 1, 64 do waveform[n] = 0 end
   
   softcut.event_render(on_render)
   softcut.event_position(on_position)

   if save_on_exit then params:read(norns.state.data .. "state.pset") end
end

-- norns: keys
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function key(n, z)
   if n == 2 then
      if z == 1 then
         record()
      end

      if z == 0 and recording then
         play()
      end
   end
   
   if n == 3 then
      if z == 1 then
         clear()
      end
   end
end

-- norns: encoders
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function enc(n, d)
   if n == 1 then
      params:delta("clock_tempo", d)
   end
   
   if n == 2 then
      params:delta("cv_1", d)
   end
   
   if n == 3 then
      params:delta("cv_2", d)
      params:delta("cv_3", d)
   end
end

-- arc: key
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

a.key = function(n, z)
   if n == 1 then
      if z == 1 then
         record()
      end

      if z == 0 and recording then
         play()
      end
   end

   -- reset params
   -- if n == 1 and z == 1 then
   --    params:set("rate", 1)
   --    params:set("level", 1)
   --    params:set("start", 0)
   --    params:set("length", 1)
   -- end
end

-- arc: encoders
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

a.delta = function(n, d)

   d = d * 0.135

   if n == 1 then
      params:delta("rate", d)
   end
   if n == 2 then
      params:delta("level", d)
   end
   if n == 3 then
      params:delta("start", d)
   end
   if n == 4 then
      params:delta("length", d)
   end
end

-- norns: drawing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function redraw()
   s.clear()
   
   s.aa(0)
   s.level(15)
   s.move(63, 48)
   s.font_face(3)
   s.font_size(28)
   if recording then
      s.text_center("opptak")
   elseif stopped then
      s.text_center("postskript")
   else
      s.text_center("[ … ]")
   end

   -- debug
   -- s.move(0, 8)
   -- s.font_face(1)
   -- s.font_size(8)
   -- s.text()

   s.update()
end

-- arc: drawing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function arc_redraw()   
   -- one led = 5.625 degrees
   
   a:all(0)
   
   local br = 4
   
   local start = params:get("start")
   local length = params:get("length")
   local length_full = length

   if length + start > 1 then
      length = 1 - start
   end
   
   -- e1

   for n = 1, 64 do
      local v = math.abs(waveform[n])
      local scaled = v == 0 and 0 or math.log10(1 + 9 * v) * 15
      a:led(1, n, math.floor(scaled))
   end

   a:led(1, 33, 0)
   
   if recording then
      softcut.query_position(recording_voice)
      a:led(1, math.floor(64 * playback_position / prev_press_time) + 32 % 64 + 1, math.floor(15 * level * 0.5))
   else
      softcut.query_position(playing_voice)
      a:led(1, math.floor(64 * playback_position / press_time) + 32 % 64 + 1, math.floor(15 * level * 0.5))
   end

   -- e2
   local s1 = 5.625 * -31
   local s2 = util.clamp(5.625 * -31 + 5.625 * 63 * level * 0.5, 5.625 * -31, 5.625 * 63)
   arc_segment(2, s1, s2, br)
   a:led(2, 1, 15)
   a:led(2, 33, 1)

   --e3
   local s1 = 5.625 * -31 + start * 5.625 * 62
   local s2 = util.clamp(s1 + 5.625 * 63 * length + 5.625, 5.625 * -32, 5.625 * 32)
   local s3 = 5.625 * -30 + start * 5.625 * 62
   local s4 = util.clamp(s3 + 5.625 * 63 * length_full, 5.625 * -32, 5.625 * 128)
   arc_segment(3, s3, s4, 1)
   arc_segment(3, s1, s2, br)
   a:led(3, 33, 15)
   
   -- e4
   local s1 = 5.625 * -31 * length_full
   local s2 = 5.625 * 0
   arc_segment(4, s1, s2, 1)

   local s1 = 5.625 * 1
   local s2 = 5.625 * 1 + 5.625 * 31 * length_full
   arc_segment(4, s1, s2, 1)

   local s1 = 5.625 * -31 * length
   local s2 = 5.625 * 0
   arc_segment(4, s1, s2, br + 1)

   local s1 = 5.625 * 1
   local s2 = 5.625 * 1 + 5.625 * 31 * length
   arc_segment(4, s1, s2, br + 1)
   a:led(4, 1, 15)
      
   a:refresh()

end

-- cleanup
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function cleanup()
   if save_on_exit then params:write(norns.state.data .. "state.pset") end
end
