gl.setup(1280, 720)
-- gl.setup(1920, 1080)

local json = require "json"
local schedule
local current_room
local coltex

util.resource_loader{
    "crossfade.frag";
}

local white = resource.create_colored_texture(1,1,1)
local rooms
local spacer = white

util.file_watch("schedule.json", function(content)
    print("reloading schedule")
    schedule = json.decode(content)
end)

node.event("config_update", function(config)
    rooms = {}
    for idx, room in ipairs(config.rooms) do
        if room.serial == sys.get_env("SERIAL") then
            print("found my room")
            current_room = room
        end
        rooms[room.name] = room
    end
    spacer = resource.create_colored_texture(CONFIG.fgcolor1.rgba())

    coltex = {
        resource.create_colored_texture(CONFIG.bgcolor1.rgba()),
        resource.create_colored_texture(CONFIG.bgcolor2.rgba()),
        resource.create_colored_texture(CONFIG.bgcolor3.rgba()),
    }
end)

hosted_init()

local base_time = N.base_time or 0
local current_talk
local all_talks = {}
local day = 0

function get_now()
    return base_time + sys.now()
end

function check_next_talk()
    local now = get_now()
    local room_next = {}
    for idx, talk in ipairs(schedule) do
        if rooms[talk.place] and not room_next[talk.place] and talk.start_unix + 25 * 60 > now then
            room_next[talk.place] = talk
        end
    end

    for room, talk in pairs(room_next) do
        talk.slide_lines = wrap(talk.title, 30)

        talk.title_lines = wrap(talk.title, 50)
        talk.speaker_line = table.concat(talk.speakers, ", ")
    end

    if room_next[current_room.name] then
        current_talk = room_next[current_room.name]
    else
        current_talk = nil
    end

    all_talks = {}
    for room, talk in pairs(room_next) do
        if current_talk and room ~= current_talk.place then
            all_talks[#all_talks + 1] = talk
        end
    end
    table.sort(all_talks, function(a, b)
        if a.start_unix < b.start_unix then
            return true
        elseif a.start_unix > b.start_unix then
            return false
        else
            return a.place < b.place
        end
    end)
end

function wrap(str, limit, indent, indent1)
    limit = limit or 72
    local here = 1
    local wrapped = str:gsub("(%s+)()(%S+)()", function(sp, st, word, fi)
        if fi-here > limit then
            here = st
            return "\n"..word
        end
    end)
    local splitted = {}
    for token in string.gmatch(wrapped, "[^\n]+") do
        splitted[#splitted + 1] = token
    end
    return splitted
end

local clock = (function()
    local base_time = N.base_time or 0

    local function set(time)
        base_time = tonumber(time) - sys.now()
    end

    util.data_mapper{
        ["clock/midnight"] = function(since_midnight)
            print("NEW midnight", since_midnight)
            set(since_midnight)
        end;
    }

    local function get()
        local time = (base_time + sys.now()) % 86400
        return string.format("%02d:%02d", math.floor(time / 3600), math.floor(time % 3600 / 60))
    end

    return {
        get = get;
        set = set;
    }
end)()

util.data_mapper{
    ["clock/set"] = function(time)
        base_time = tonumber(time) - sys.now()
        N.base_time = base_time
        check_next_talk()
        -- print("UPDATED TIME", base_time)
    end;
    ["clock/day"] = function(new_day)
        day = new_day
        -- print("UPDATED DAY", new_day)
    end;
}

function switcher(get_screens)
    local current_idx = 0
    local current
    local current_state

    local switch = sys.now()
    local switched = sys.now()

    local blend = 0.8
    local mode = "switch"

    local old_screen
    local current_screen

    local screens = get_screens()

    local function prepare()
        local now = sys.now()
        if now - switched > blend and mode == "switch" then
            if current_screen then
                current_screen:dispose()
            end
            if old_screen then
                old_screen:dispose()
            end
            current_screen = nil
            old_screen = nil
            mode = "show"
        elseif now > switch and mode == "show" then
            mode = "switch"
            switched = now

            -- snapshot old screen
            gl.clear(0.5, 0.5, 0.5, 0.0)
            if current then
                current.draw(current_state)
            end
            old_screen = resource.create_snapshot(0, 170, WIDTH, HEIGHT-170)

            -- find next screen
            current_idx = current_idx + 1
            if current_idx > #screens then
                screens = get_screens()
                current_idx = 1
            end
            current = screens[current_idx]
            switch = now + current.time
            current_state = current.prepare()

            -- snapshot next screen
            gl.clear(0.5, 0.5, 0.5, 0.0)
            current.draw(current_state)
            current_screen = resource.create_snapshot(0, 170, WIDTH, HEIGHT-170)
        end
    end

    local function draw()
        local now = sys.now()
        local progress = ((now - switched) / (switch - switched))

        if mode == "switch" then
            local progress = (now - switched) / blend
            if CONFIG.transition == "rotate" then
                gl.pushMatrix()
                gl.translate(WIDTH/2, 0)
                if progress < 0.5 then
                    gl.rotate(180 * progress, 0, 1, 0)
                    gl.translate(-WIDTH/2, 0)
                    old_screen:draw(0, 170, WIDTH, HEIGHT)
                else
                    gl.rotate(180 + 180 * progress, 0, 1, 0)
                    gl.translate(-WIDTH/2, 0)
                    current_screen:draw(0, 170, WIDTH, HEIGHT)
                end
                gl.popMatrix()
            elseif CONFIG.transition == "crossfade" then
                crossfade:use{
                    Old = old_screen;
                    progress = progress;
                    one_minus_progress = 1 - progress;
                }
                current_screen:draw(0, 170, WIDTH, HEIGHT)
                crossfade:deactivate()
            end
        else
            current.draw(current_state)
        end

        local ad_size = 13
        local ad_text = "@infobeamer"
        local width = CONFIG.font:width(ad_text, ad_size)
        CONFIG.font:write(WIDTH-18-width, HEIGHT-18, ad_text, ad_size, 1,1,1,.8)

        white:draw(0, HEIGHT-2, WIDTH * progress, HEIGHT, 0.3)
    end
    return {
        prepare = prepare;
        draw = draw;
    }
end

local content = switcher(function()
    local screens = {}
    local function add_screen_if(condition, screen)
        if condition then
            screens[#screens+1] = screen
        end
    end

    add_screen_if(CONFIG.current_room > 0, {
        time = CONFIG.current_room,
        prepare = function()
        end;
        draw = function()
            if not current_talk then
                CONFIG.font:write(70, 170, "next talk", 80, CONFIG.header_color.rgba())
                coltex[1]:draw(0, 281, WIDTH, 900, 0.9)
                CONFIG.font:write(70, 330, "nope. That's it.", 50, CONFIG.fgcolor1.rgba())
            else
                local delta = current_talk.start_unix - get_now()
                if delta > 0 then
                    CONFIG.font:write(70, 170, "next talk", 80, CONFIG.header_color.rgba())
                else
                    CONFIG.font:write(70, 170, "this talk", 80, CONFIG.header_color.rgba())
                end
                coltex[1]:draw(0, 281, WIDTH, 900, 0.9)

                CONFIG.font:write(70, 330, current_talk.start_str, 50, CONFIG.fgcolor1.rgba())
                if delta > 180*60 then
                    CONFIG.font:write(70, 330 + 60, string.format("in %d h", math.floor(delta/3600)), 50, CONFIG.fgcolor1.rgba())
                elseif delta > 0 then
                    CONFIG.font:write(70, 330 + 60, string.format("in %d min", math.floor(delta/60)+1), 50, CONFIG.fgcolor1.rgba())
                end
                for idx, line in ipairs(current_talk.slide_lines) do
                    if idx >= 5 then
                        break
                    end
                    CONFIG.font:write(420, 330 - 60 + 50 * idx, line, 50, CONFIG.fgcolor1.rgba())
                end
                for i, speaker in ipairs(current_talk.speakers) do
                    CONFIG.font:write(420 + ((i-1)%2) * 350, 550 + 30 * math.floor((i-1)/2), speaker, 30, CONFIG.fgcolor1.rgba())
                end
            end
        end
    })

    add_screen_if(CONFIG.other_rooms > 0, {
        time = CONFIG.other_rooms,
        prepare = function()
            local content = {}

            local function add_content(func)
                content[#content+1] = func
            end

            local function mk_spacer()
                return function(y)
                    spacer:draw(0, y+5, WIDTH, y+7, 0.3)
                    return 25
                end
            end

            local function mk_talk(talk, is_running)
                local alpha
                if is_running then
                    alpha = 0.5
                else
                    alpha = 1.0
                end

                return function(y)
                    CONFIG.font:write(70, y, talk.start_str, 50, CONFIG.fgcolor2.rgb_with_a(alpha))
                    CONFIG.font:write(230, y, rooms[talk.place].name_short, 50, CONFIG.fgcolor2.rgb_with_a(alpha))
                    local line_y = y
                    for idx = 1, #talk.title_lines do
                        local title = talk.title_lines[idx]
                        CONFIG.font:write(CONFIG.text_offset, line_y, title, 30, CONFIG.fgcolor2.rgb_with_a(alpha))
                        line_y = line_y + 28
                    end
                    CONFIG.font:write(CONFIG.text_offset, line_y, talk.speaker_line, 30, CONFIG.fgcolor2.rgb_with_a(alpha*0.6))
                    line_y = line_y + 28
                    return math.max(60, line_y - y) + 5
                end
            end

            local time_sep = false
            if #all_talks > 0 then
                for idx, talk in ipairs(all_talks) do
                    if not time_sep and talk.start_unix > get_now() then
                        if idx > 1 then
                            add_content(mk_spacer())
                        end
                        time_sep = true
                    end
                    add_content(mk_talk(talk, not time_sep))
                end
            else
                add_content(function()
                    CONFIG.font:write(70, 310, "no other talks.", 50, CONFIG.fgcolor2.rgba())
                    return 50
                end)
            end

            return content
        end;
        draw = function(content)
            CONFIG.font:write(70, 170, "other talks", 80, CONFIG.header_color.rgba())
            coltex[2]:draw(0, 281, WIDTH, 900, 0.9)
            local y = 330
            for _, func in ipairs(content) do
                y = y + func(y)
            end
        end
    })

    add_screen_if(CONFIG.room_info > 0, {
        time = CONFIG.room_info,
        prepare = function()
        end;
        draw = function()
            CONFIG.font:write(70, 170, "room information", 80, CONFIG.header_color.rgba())
            coltex[3]:draw(0, 281, WIDTH, 900, 0.9)
            local y = 330

            -- CONFIG.font:write(70, y, "audio", 50, CONFIG.fgcolor3.rgba())
            -- CONFIG.font:write(420, y, current_room.dect, 50, CONFIG.fgcolor3.rgba())

            -- y = y + 50
            -- CONFIG.font:write(70, y, "translation", 50, CONFIG.fgcolor3.rgba())
            -- CONFIG.font:write(420, y, current_room.translation, 50, CONFIG.fgcolor3.rgba())
            -- y = y + 50 + 25
            --
            CONFIG.font:write(70, y, "irc", 50, CONFIG.fgcolor3.rgba())
            CONFIG.font:write(420, y, current_room.irc, 50, CONFIG.fgcolor3.rgba())

            y = y + 50
            CONFIG.font:write(70, y, "hashtag", 50, CONFIG.fgcolor3.rgba())
            CONFIG.font:write(420, y, current_room.hashtag, 50, CONFIG.fgcolor3.rgba())
        end
    })

    return screens
end)

function node.render()
    if base_time == 0 then
        gl.clear(0,0,0,1)
        CONFIG.background.ensure_loaded():draw(0, 0, WIDTH, HEIGHT)
        local w = CONFIG.font:width("loading...", 50)
        CONFIG.font:write((WIDTH - w) / 2, HEIGHT/2 - 25, "loading...", 50, 1, 1, 1, 1)
        return
    end

    content.prepare()
    gl.clear(0,0,0,1)
    CONFIG.background.ensure_loaded():draw(0, 0, WIDTH, HEIGHT)

    CONFIG.font:write(70, 42, clock.get(), 50, CONFIG.header_color.rgb_with_a(0.8))
    CONFIG.font:write(250, 42, current_room.name_short, 50, CONFIG.header_color.rgb_with_a(0.8))
    CONFIG.font:write(70, 92, "day " .. day, 50, CONFIG.header_color.rgb_with_a(0.8))

    local fov = math.atan2(HEIGHT, WIDTH*2) * 360 / math.pi
    gl.perspective(fov, WIDTH/2, HEIGHT/2, -WIDTH,
                        WIDTH/2, HEIGHT/2, 0)
    content.draw()
end
