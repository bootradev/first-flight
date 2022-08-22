const data = @import("data.zig");
const std = @import("std");
const w4 = @import("wasm4.zig");

pub const ItemKind = enum {
    ring,
    speed_up,
};

pub const Item = struct {
    kind: ItemKind,
    x: f32,
    y: f32,
    h: f32,
};

pub const LeaderboardEntry = struct {
    initials: []const u8,
    score: usize,
    time: f32,
};

pub const IntroLine = struct {
    x: i32,
    y: i32,
    text: []const u8,
};

pub const Level = struct {
    name: []const u8,
    intro: []const IntroLine,
    ground: []const u8,
    items: []const Item,
    leaderboard: []const LeaderboardEntry,
};

pub const Note = struct {
    start: u32,
    end: u32,
    freq: u32,
};

pub const NoteSequence = struct {
    notes: []const Note,
    beat_count: usize,
    repeat: u32,
};

pub const Song = struct {
    lead: []const NoteSequence,
    bass: []const NoteSequence,
    loop: bool,
};

const NoteSequenceRuntime = struct {
    beat: u32,
    repeat_count: u32,
    sequence_index: usize,
    note_index: usize,
};

const SongRuntime = struct {
    lead: NoteSequenceRuntime,
    bass: NoteSequenceRuntime,
};

const SaveData = struct {
    initials: [3]u8,
    leaderboard_entries: [levels.len]LeaderboardEntry,
};

// constants
const menu_entry_offset_x = 40;
const menu_selected_offset_x = menu_entry_offset_x - 11;
const menu_entry_offset_y = 19;
const menu_entry_offset_y_interval = 12;

const cam_near = 0.005;
const cam_far = 0.3;
const cam_fov_2 = std.math.pi / 4.0;
const cam_accel_x = 4.0;
const cam_accel_y = 1.0;
const cam_accel_h = 2.5;
const cam_max_vel_x = 0.5;
const cam_max_vel_y = 0.3;
const cam_max_vel_h = 0.25;
const cam_damp_vel_x = 0.9;
const cam_damp_vel_y = 0.99;
const cam_damp_vel_h = 0.9;
const cam_max_vel_y_speed_up = 0.6;
const cam_min_x = -0.5;
const cam_max_x = 0.5;
const cam_min_h = -0.2;
const cam_max_h = 0.4;

const ground_size = 64;
const ground_scroll_speed = 1.5;

const level_wait_time_total = 5.0;
const level_waiting_text_height = 140;

const player_draw_height = 81;
const item_size = 60;

const obj_height_scale = 1000.0;
const obj_depth_scale = 100.0;
const obj_collect_dist = 0.1;

const font_glyph_width = 8;
const time_mod = 1.0;

const song_frames_per_beat = 1;
const song_menu = &data.song3;
const song_level = &data.song2;
const song_level_complete = &data.song1;

const levels = [_]Level{ data.level1, data.level2, data.level3 };

// global variables
var gamepad: u8 = 0;
var gamepad_this_frame: u8 = 0;
var last_gamepad: u8 = 0;

var cam_max_vel_y_mod: f32 = 0.0;

var cam_vel_x: f32 = 0.0;
var cam_vel_y: f32 = 0.0;
var cam_vel_h: f32 = 0.0;

var cam_x: f32 = 0.0;
var cam_y: f32 = 0.0;
var cam_h: f32 = 0.0;
var cam_angle: f32 = 0.0;

var is_in_menu: bool = true;
var is_in_title: bool = true;
var is_in_leaderboard: bool = false;
var is_in_create_save: bool = false;
var is_in_level_intro: bool = false;
var returning_from_level: bool = false;
var menu_selection: usize = 0;
var leaderboard_index: usize = 0;

var level_index: usize = 0;
var level_item_index: usize = 0;
var level_spawn_y: f32 = 0;
var level_score: u8 = 0;
var level_time: f32 = 0.0;
var level_waiting: bool = false;
var level_wait_time: f32 = 0.0;
var level_complete: bool = false;
var level_countdown_horn: u32 = 0;

var items: [8]Item = undefined;

var frame: usize = 0;

var saved: ?SaveData = null;
var save_initial_count: usize = 0;

var song_playing: *const Song = undefined;
var song_runtime: SongRuntime = undefined;
var music_enabled: bool = true;

var item_collect_frame: usize = 0;

export fn start() void {
    w4.PALETTE.* = [4]u32{ 0xEDE6DF, 0xC7AFF0, 0x645991, 0x2B233B };

    // clear data
    // _ = w4.diskw(undefined, 0);

    var save_data_read: SaveData = undefined;
    const read_count = w4.diskr(@ptrCast([*]u8, &save_data_read), @sizeOf(SaveData));
    if (read_count == @sizeOf(SaveData)) {
        saved = save_data_read;
    }

    playSong(song_menu);
}

export fn update() void {
    gamepad = w4.GAMEPAD1.*;
    gamepad_this_frame = gamepad & (gamepad ^ last_gamepad);

    if (is_in_menu) {
        updateMenu();
    } else {
        updateBackground();
        updateItems();
        updatePlayer();
        updateLevel();
    }
    updateMusic();

    frame += 1;
    last_gamepad = gamepad;
}

fn updateMenu() void {
    w4.DRAW_COLORS.* = 0x13;

    const max_level_index = levels.len - 1;

    if (is_in_create_save) {
        w4.DRAW_COLORS.* = 0x22;
        w4.rect(0, 0, w4.SCREEN_SIZE, w4.SCREEN_SIZE);

        w4.DRAW_COLORS.* = 0x1;
        w4.text("High score!", 36, 10);
        w4.text("Enter initials: ", 20, 20);

        w4.text(saved.?.initials[0..save_initial_count], 68, 64);
        w4.hline(68, 72, 7);
        w4.hline(76, 72, 7);
        w4.hline(84, 72, 7);

        w4.text("Press Left or Right", 5, menu_entry_offset_y + 94);
        w4.text("to change letter.", 5, menu_entry_offset_y + 104);
        w4.text("Press X to enter.", 5, menu_entry_offset_y + 114);
        w4.text("Press Z to delete.", 5, menu_entry_offset_y + 124);

        const cur_initial_idx = save_initial_count - 1;
        const cur_initial = saved.?.initials[save_initial_count - 1];
        if (buttonPressedThisFrame(w4.BUTTON_LEFT)) {
            saved.?.initials[cur_initial_idx] = if (cur_initial == 'A') 'Z' else cur_initial - 1;
            playUiMove();
        }

        if (buttonPressedThisFrame(w4.BUTTON_RIGHT)) {
            saved.?.initials[cur_initial_idx] = if (cur_initial == 'Z') 'A' else cur_initial + 1;
            playUiMove();
        }

        if (buttonPressedThisFrame(w4.BUTTON_2)) {
            if (save_initial_count > 1) {
                save_initial_count -= 1;
                playUiSelect();
            }
        }

        if (buttonPressedThisFrame(w4.BUTTON_1)) {
            if (save_initial_count == saved.?.initials.len) {
                _ = w4.diskw(@ptrCast([*]const u8, &saved.?), @sizeOf(SaveData));
                is_in_create_save = false;
                is_in_leaderboard = true;
                leaderboard_index = level_index;
            } else {
                saved.?.initials[save_initial_count] = 'A';
                save_initial_count += 1;
            }
            playUiSelect();
        }
    } else if (is_in_leaderboard) {
        const level_name = levels[leaderboard_index].name;

        w4.DRAW_COLORS.* = 0x22;
        w4.rect(0, 0, w4.SCREEN_SIZE, w4.SCREEN_SIZE);

        w4.DRAW_COLORS.* = 0x1;
        const total_length = 92 + level_name.len * 8;
        const start_x = @intCast(i32, (w4.SCREEN_SIZE - total_length) / 2);
        w4.text("High", start_x, 4);
        w4.text("Scores:", start_x + 36, 4);
        w4.text(level_name, start_x + 93, 4);
        w4.hline(9, 13, 142);

        const player_entry = if (saved) |s| s.leaderboard_entries[leaderboard_index] else null;
        var needs_draw_player_entry = player_entry != null;

        const offset_x = 28;
        var offset_y: i32 = 20;
        var entry_idx: usize = 0;
        var num_entries: usize = 0;
        while (num_entries < levels[leaderboard_index].leaderboard.len) : (num_entries += 1) {
            var draw_entry = levels[leaderboard_index].leaderboard[entry_idx];
            if (needs_draw_player_entry and
                (player_entry.?.score > draw_entry.score or
                (player_entry.?.score == draw_entry.score and player_entry.?.time < draw_entry.time)))
            {
                draw_entry = player_entry.?;
                draw_entry.initials = saved.?.initials[0..];
                needs_draw_player_entry = false;
                drawSelIcon(@floatToInt(i32, offset_x - 11), offset_y);
                w4.DRAW_COLORS.* = 0x3;
            } else {
                entry_idx += 1;
                w4.DRAW_COLORS.* = 0x1;
            }

            w4.text(draw_entry.initials, offset_x, offset_y);
            drawNumberText(draw_entry.score, offset_x + 40, offset_y);
            w4.text("(", offset_x + 50, offset_y);
            drawTime(draw_entry.time, offset_x + 43, offset_y);
            w4.text(")", offset_x + 100, offset_y);
            offset_y += menu_entry_offset_y_interval;
        }

        w4.DRAW_COLORS.* = 0x1;
        w4.text("Press X to continue.", 2, 145);

        if (buttonPressedThisFrame(w4.BUTTON_1)) {
            if (returning_from_level) {
                returning_from_level = false;
                is_in_leaderboard = false;
                leaderboard_index = 0;
            } else if (leaderboard_index == max_level_index) {
                is_in_leaderboard = false;
                leaderboard_index = 0;
            } else {
                leaderboard_index += 1;
            }
            playUiSelect();
        }
    } else if (is_in_level_intro) {
        w4.DRAW_COLORS.* = 0x4321;
        w4.blit(&data.title, 0, 0, data.title_width, data.title_height, data.title_flags);
        w4.DRAW_COLORS.* = 0x22;
        w4.rect(0, 0, w4.SCREEN_SIZE, 100);

        w4.DRAW_COLORS.* = 0x4321;
        w4.blit(
            &data.witchgirl,
            0,
            w4.SCREEN_SIZE - data.witchgirl_height,
            data.witchgirl_width,
            data.witchgirl_height,
            data.witchgirl_flags,
        );

        const stars_x = [_]usize{ 14, 8, 18, 6, 2, 78, 77, 99, 131, 155, 140, 153, 147, 93, 110, 130 };
        const stars_y = [_]usize{ 8, 29, 42, 80, 118, 100, 127, 105, 103, 105, 97, 77, 12, 78, 93, 72 };
        const stars_count = stars_x.len;

        var star_index: usize = 0;
        while (star_index < stars_count) : (star_index += 1) {
            setFramebufferPixel(stars_x[star_index], stars_y[star_index], 0x0);
        }

        w4.DRAW_COLORS.* = 0x1;
        for (levels[menu_selection].intro) |intro| {
            w4.text(intro.text, intro.x, intro.y);
        }
        w4.text("Press X to begin!", 10, 150);

        if (buttonPressedThisFrame(w4.BUTTON_1)) {
            is_in_menu = false;
            is_in_level_intro = false;

            startLevel(menu_selection);
            playUiSelect();
        }
    } else if (is_in_title) {
        w4.DRAW_COLORS.* = 0x4321;
        w4.blit(&data.title, 0, 0, data.title_width, data.title_height, data.title_flags);

        w4.DRAW_COLORS.* = 0x01;
        w4.text("Press X to begin!", 10, 100);

        if (buttonPressedThisFrame(w4.BUTTON_1)) {
            is_in_title = false;
            playUiSelect();
        }
    } else {
        w4.DRAW_COLORS.* = 0x4321;
        w4.blit(&data.title, 0, 0, data.title_width, data.title_height, data.title_flags);

        w4.DRAW_COLORS.* = 0x22;
        w4.rect(0, 0, w4.SCREEN_SIZE, 100);

        const stars_x = [_]usize{ 16, 4, 17, 7, 131, 147, 153, 148, 154, 26, 19, 128, 138, 47 };
        const stars_y = [_]usize{ 7, 23, 31, 57, 5, 18, 41, 57, 76, 49, 68, 30, 72, 111 };
        const stars_count = stars_x.len;

        var star_index: usize = 0;
        while (star_index < stars_count) : (star_index += 1) {
            setFramebufferPixel(stars_x[star_index], stars_y[star_index], 0x0);
        }

        w4.DRAW_COLORS.* = 0x1;
        w4.text("Main Menu", 40, 5);
        w4.hline(39, 14, 74);

        const max_menu_selection = max_level_index + 2;
        const color_unfocused = 0x1;
        const color_focused = 0x3;

        var offset_y: i32 = menu_entry_offset_y;
        for (levels) |level, i| {
            w4.DRAW_COLORS.* = color_unfocused;
            if (menu_selection == i) {
                drawSelIcon(@floatToInt(i32, menu_selected_offset_x), offset_y);
                w4.DRAW_COLORS.* = color_focused;
            }
            w4.text(level.name, menu_entry_offset_x, offset_y);
            offset_y += menu_entry_offset_y_interval;
        }

        w4.DRAW_COLORS.* = color_unfocused;
        if (menu_selection == max_level_index + 1) {
            drawSelIcon(@floatToInt(i32, menu_selected_offset_x), offset_y);
            w4.DRAW_COLORS.* = color_focused;
        }
        w4.text("High Scores", menu_entry_offset_x, offset_y);

        offset_y += menu_entry_offset_y_interval;
        w4.DRAW_COLORS.* = color_unfocused;
        if (menu_selection == max_level_index + 2) {
            drawSelIcon(@floatToInt(i32, menu_selected_offset_x), offset_y);
            w4.DRAW_COLORS.* = color_focused;
        }
        w4.text("Music: ", menu_entry_offset_x, offset_y);
        w4.text(if (music_enabled) "On" else "Off", menu_entry_offset_x + 48, offset_y);

        w4.DRAW_COLORS.* = color_unfocused;
        w4.text("Press Up and Down", 10, menu_entry_offset_y + 61);
        w4.text("to move selection.", 10, menu_entry_offset_y + 71);
        w4.text("Press X to select.", 10, menu_entry_offset_y + 81);

        if (buttonPressedThisFrame(w4.BUTTON_UP)) {
            menu_selection = if (menu_selection == 0) max_menu_selection else menu_selection - 1;
            playUiMove();
        }

        if (buttonPressedThisFrame(w4.BUTTON_DOWN)) {
            menu_selection = if (menu_selection == max_menu_selection) 0 else menu_selection + 1;
            playUiMove();
        }

        if (buttonPressedThisFrame(w4.BUTTON_1)) {
            if (menu_selection >= 0 and menu_selection <= max_level_index) {
                is_in_level_intro = true;
                playSong(song_level);
            } else if (menu_selection == max_level_index + 1) {
                is_in_leaderboard = true;
            } else if (menu_selection == max_level_index + 2) {
                music_enabled = !music_enabled;
            }
            playUiSelect();
        }
    }
}

fn updateBackground() void {
    w4.DRAW_COLORS.* = 0x4321;
    w4.blit(&data.background, 0, 0, data.background_width, data.background_height, data.background_flags);

    // draw mode7
    // we can use the far plane to fake camera y movement
    const cam_far_height = cam_far + cam_h;
    const cam_y_scroll = cam_y * ground_scroll_speed;

    const far_x1 = cam_x + cos(cam_angle + cam_fov_2) * cam_far_height;
    const far_y1 = cam_y_scroll + sin(cam_angle + cam_fov_2) * cam_far_height;

    const near_x1 = cam_x + cos(cam_angle + cam_fov_2) * cam_near;
    const near_y1 = cam_y_scroll + sin(cam_angle + cam_fov_2) * cam_near;

    const far_x2 = cam_x + cos(cam_angle - cam_fov_2) * cam_far_height;
    const far_y2 = cam_y_scroll + sin(cam_angle - cam_fov_2) * cam_far_height;

    const near_x2 = cam_x + cos(cam_angle - cam_fov_2) * cam_near;
    const near_y2 = cam_y_scroll + sin(cam_angle - cam_fov_2) * cam_near;

    // near the horizon looks a bit rough, chop it off
    const horizon_start = 10;
    w4.DRAW_COLORS.* = 0x33;
    w4.rect(0, w4.SCREEN_SIZE / 2, w4.SCREEN_SIZE, horizon_start);
    var y: usize = horizon_start;
    while (y < w4.SCREEN_SIZE / 2) : (y += 1) {
        const depth = @intToFloat(f32, y) / @intToFloat(f32, w4.SCREEN_SIZE / 2);

        const start_x = (far_x1 - near_x1) / depth + near_x1;
        const start_y = (far_y1 - near_y1) / depth + near_y1;

        const end_x = (far_x2 - near_x2) / depth + near_x2;
        const end_y = (far_y2 - near_y2) / depth + near_y2;

        var x: usize = 0;
        while (x < w4.SCREEN_SIZE) : (x += 1) {
            const width = @intToFloat(f32, x) / @intToFloat(f32, w4.SCREEN_SIZE);

            const sample_x = @mod((end_x - start_x) * width + start_x + 0.5, 1.0);
            const sample_y = 1.0 - @mod((end_y - start_y) * width + start_y, 1.0);

            const pixel = getGroundPixel(sample_x, sample_y);
            setFramebufferPixel(x, y + @as(u8, w4.SCREEN_SIZE / 2), pixel);
        }
    }
}

fn updateItems() void {
    for (items) |*item| {
        const item_xdir = item.x - cam_x;
        const item_ydir = item.y - cam_y;

        const item_diff = atan2(item_xdir, item_ydir);
        const cam_diff = atan2(cos(cam_angle), sin(cam_angle));
        const angle_diff = @mod((item_diff - cam_diff) + std.math.pi, std.math.tau) - std.math.pi;

        const far_obj = item_size / obj_depth_scale;
        const far_sq = far_obj * far_obj;
        const depth_sq = item_xdir * item_xdir + item_ydir * item_ydir;
        // magic numbers to create a nice depth curve that scales from 1.0 to 0.0
        const depth_ratio = (1.0 / (10.0 * (depth_sq / far_sq + 0.1) - 0.1));

        // not a perfect culling test, but good enough
        if (@fabs(angle_diff) > (cam_fov_2 * 2.0) or depth_ratio < 0.0 or depth_ratio > 1.0) {
            continue;
        }

        const ss = @as(f32, w4.SCREEN_SIZE);
        const x = ((angle_diff / cam_fov_2 + 1.0) / 2.0) * ss;
        const y = (depth_ratio * (cam_h - item.h) * obj_height_scale) + ss / 2.0;
        const size = depth_ratio * item_size * 0.75;

        // check if we collect the item
        if (@fabs(cam_y - item.y) < obj_collect_dist) {
            if (@fabs(x - @as(f32, w4.SCREEN_SIZE) / 2.0) < size and
                @fabs(y - @as(f32, player_draw_height + data.witch_height / 2)) < size)
            {
                collectItem(item);
            } else {
                missItem(item);
            }

            spawnItem(item);
            continue;
        }

        switch (item.kind) {
            .ring => drawRing(x, y, size),
            .speed_up => drawSpeedUp(x, y, size),
        }
    }

    updatePlayRingCollect();
}

fn drawRing(x: f32, y: f32, size: f32) void {
    if (size < 6.0) {
        w4.DRAW_COLORS.* = 0x10;
        const size2 = @floatToInt(i32, size * 2);
        const offset = @divExact(size2, 2);
        w4.oval(@floatToInt(i32, x) - offset, @floatToInt(i32, y) - offset, size2, size2);
    } else {
        // optimize me: create quarter sprites for each possible radius
        var i: usize = 0;
        const num_steps = @floatToInt(usize, size * size);
        while (i < num_steps) : (i += 1) {
            const a: f32 = (std.math.tau / @intToFloat(f32, num_steps)) * @intToFloat(f32, i);
            const draw_x = @floatToInt(usize, x + cos(a) * size);
            const draw_y = @floatToInt(usize, y + sin(a) * size);

            setFramebufferPixel(draw_x, draw_y, 0b00);
            setFramebufferPixel(draw_x + 1, draw_y, 0b00);
            if (size > 20) {
                setFramebufferPixel(draw_x - 1, draw_y, 0b00);
            }

            if (size > 25) {
                setFramebufferPixel(draw_x, draw_y + 1, 0b00);
                setFramebufferPixel(draw_x, draw_y - 1, 0b00);
            }
        }
    }
}

fn drawSpeedUp(x: f32, y: f32, size: f32) void {
    const w = @floatToInt(u32, size);
    const h = w / 4;
    const offset = @intCast(i32, w / 2);
    const offset_h = @intCast(i32, h / 2);
    w4.DRAW_COLORS.* = 0x11;
    w4.rect(@floatToInt(i32, x) - offset, @floatToInt(i32, y) - offset_h, w, h);
    w4.rect(@floatToInt(i32, x) - offset_h, @floatToInt(i32, y) - offset, h, w);
}

fn collectItem(item: *const Item) void {
    switch (item.kind) {
        .ring => {
            playRingCollect();
            level_score += 1;
        },
        .speed_up => {
            cam_max_vel_y_mod = cam_max_vel_y_speed_up;
            playSpeedUpCollect();
        },
    }
}

fn missItem(item: *const Item) void {
    switch (item.kind) {
        .ring => {
            playRingMiss();
        },
        else => {},
    }
}

fn updatePlayer() void {
    var anim_state: u32 = 0;

    if (!level_waiting and !level_complete) {
        if (buttonPressed(w4.BUTTON_LEFT)) {
            cam_vel_x -= cam_accel_x / 60.0;
            anim_state = 1;
        }

        if (buttonPressed(w4.BUTTON_RIGHT)) {
            cam_vel_x += cam_accel_x / 60.0;
            anim_state = 2;
        }

        if (buttonPressed(w4.BUTTON_UP)) {
            cam_vel_h += cam_accel_h / 60.0;
        }

        if (buttonPressed(w4.BUTTON_DOWN)) {
            cam_vel_h -= cam_accel_h / 60.0;
        }

        if (buttonPressed(w4.BUTTON_1)) {
            cam_vel_y += cam_accel_y / 60.0;
        }

        if (buttonPressed(w4.BUTTON_2)) {
            cam_vel_y -= cam_accel_y / 60.0;
        }

        cam_max_vel_y_mod = (1.0 / 60.0) * (cam_max_vel_y - cam_max_vel_y_mod) + cam_max_vel_y_mod;

        cam_vel_x = cam_damp_vel_x * std.math.clamp(cam_vel_x, -cam_max_vel_x, cam_max_vel_x);
        cam_vel_y = cam_damp_vel_y * std.math.clamp(cam_vel_y, 0.0, cam_max_vel_y_mod);
        cam_vel_h = cam_damp_vel_h * std.math.clamp(cam_vel_h, -cam_max_vel_h, cam_max_vel_h);

        cam_x += cam_vel_x / 60.0;
        cam_y += cam_vel_y / 60.0;
        cam_h += cam_vel_h / 60.0;

        cam_x = std.math.clamp(cam_x, cam_min_x, cam_max_x);
        cam_h = std.math.clamp(cam_h, cam_min_h, cam_max_h);
    }

    w4.DRAW_COLORS.* = 0x0432;
    if (anim_state == 0) {
        w4.blit(
            &data.witch,
            w4.SCREEN_SIZE / 2 - data.witch_width / 2,
            player_draw_height,
            data.witch_width,
            data.witch_height,
            data.witch_flags,
        );
    } else if (anim_state == 1) {
        w4.blit(
            &data.witch_l,
            w4.SCREEN_SIZE / 2 - data.witch_l_width / 2,
            player_draw_height,
            data.witch_l_width,
            data.witch_l_height,
            data.witch_l_flags,
        );
    } else if (anim_state == 2) {
        w4.blit(
            &data.witch_r,
            w4.SCREEN_SIZE / 2 - data.witch_r_width / 2,
            player_draw_height,
            data.witch_r_width,
            data.witch_r_height,
            data.witch_r_flags,
        );
    }
}

fn updateLevel() void {
    w4.DRAW_COLORS.* = 0x01;

    w4.text("Time:", 78, 0);
    drawTime(level_time, 104, 0);

    w4.text("Score:", 2, 0);
    drawNumberText(level_score, 2 + 54, 0);

    if (level_time > 99.99) {
        level_complete = true;
    }

    if (level_wait_time > -1.0) {
        if (level_wait_time > 3.0) {
            w4.text("Get ready!", 40, level_waiting_text_height);
        } else if (level_wait_time > 2.0) {
            w4.text("3", 76, level_waiting_text_height);
            if (level_countdown_horn == 0) {
                playCountdownHorn();
                level_countdown_horn += 1;
            }
        } else if (level_wait_time > 1.0) {
            w4.text("2", 76, level_waiting_text_height);
            if (level_countdown_horn == 1) {
                playCountdownHorn();
                level_countdown_horn += 1;
            }
        } else if (level_wait_time > 0.0) {
            w4.text("1", 76, level_waiting_text_height);
            if (level_countdown_horn == 2) {
                playCountdownHorn();
                level_countdown_horn += 1;
            }
        } else if (level_wait_time > -1.0) {
            w4.text("Go!", 70, level_waiting_text_height);
            level_waiting = false;
            if (level_countdown_horn == 3) {
                playCountdownHornGo();
                level_countdown_horn += 1;
            }
        }

        level_wait_time -= (1.0 / 60.0) * time_mod;
    } else if (level_complete) {
        w4.text("Level complete!", 20, 140);
        w4.text("Press X to continue.", 2, 150);

        if (buttonPressedThisFrame(w4.BUTTON_1)) {
            is_in_menu = true;
            returning_from_level = true;

            // save level score before going back to menu
            if (saved) |*s| {
                var cur_entry = &s.leaderboard_entries[level_index];
                if (level_score > cur_entry.score or
                    (level_score == cur_entry.score and level_time < cur_entry.time))
                {
                    s.leaderboard_entries[level_index].initials = s.initials[0..];
                    s.leaderboard_entries[level_index].score = level_score;
                    s.leaderboard_entries[level_index].time = level_time;
                    _ = w4.diskw(@ptrCast([*]const u8, s), @sizeOf(SaveData));
                }
                is_in_leaderboard = true;
                leaderboard_index = level_index;
            } else {
                is_in_create_save = true;
                var new_saved: SaveData = undefined;
                saved = new_saved;
                saved.?.initials[0] = 'A';
                save_initial_count = 1;
                var i: usize = 0;
                while (i < levels.len) : (i += 1) {
                    if (i == level_index) {
                        saved.?.leaderboard_entries[i].score = level_score;
                        saved.?.leaderboard_entries[i].time = level_time;
                    } else {
                        saved.?.leaderboard_entries[i].score = 0;
                        saved.?.leaderboard_entries[i].time = 0.0;
                    }
                }
            }
            playSong(song_menu);
        }
    } else if (cam_y > level_spawn_y) {
        level_complete = true;
        playSong(song_level_complete);
    }

    if (!level_waiting and !level_complete) {
        level_time += (1.0 / 60.0) * time_mod;
    }
}

fn updateMusic() void {
    if (!music_enabled or frame % song_frames_per_beat != 0) {
        return;
    }

    updateNoteSequence(song_playing.lead, &song_runtime.lead, 10, w4.TONE_PULSE2, song_playing.loop);
    updateNoteSequence(song_playing.bass, &song_runtime.bass, 10, w4.TONE_TRIANGLE, song_playing.loop);
}

fn updateNoteSequence(
    sequences: []const NoteSequence,
    runtime: *NoteSequenceRuntime,
    volume: u32,
    flags: u32,
    loop: bool,
) void {
    if (sequences.len == 0 or runtime.sequence_index >= sequences.len) {
        return;
    }

    const sequence = sequences[runtime.sequence_index];
    if (sequence.notes.len > 0 and runtime.beat == sequence.notes[runtime.note_index].end) {
        if (runtime.note_index < sequence.notes.len - 1) {
            runtime.note_index += 1;
        } else {
            runtime.note_index = 0;
        }
    }
    if (sequence.notes.len > 0 and runtime.beat == sequence.notes[runtime.note_index].start) {
        const note = sequence.notes[runtime.note_index];
        w4.tone(note.freq, (note.end - note.start) * song_frames_per_beat, volume, flags);
    }

    if (runtime.beat == sequence.beat_count) {
        if (runtime.repeat_count > 1) {
            runtime.repeat_count -= 1;
        } else {
            if (runtime.sequence_index < sequences.len - 1) {
                runtime.sequence_index += 1;
            } else if (loop) {
                runtime.sequence_index = 0;
            } else {
                runtime.sequence_index += 1;
                return;
            }
            runtime.repeat_count = sequences[runtime.sequence_index].repeat;
        }

        runtime.beat = 0;
        updateNoteSequence(sequences, runtime, volume, flags, loop);
    } else {
        runtime.beat += 1;
    }
}

fn startLevel(index: usize) void {
    level_index = index;
    const level = levels[level_index];

    level_item_index = 0;
    level_spawn_y = level.items[0].y;
    level_score = 0;
    level_time = 0.0;
    level_waiting = true;
    level_wait_time = level_wait_time_total;
    level_countdown_horn = 0;
    level_complete = false;

    cam_max_vel_y_mod = cam_max_vel_y;
    cam_vel_x = 0.0;
    cam_vel_y = 0.0;
    cam_vel_h = 0.0;
    cam_x = 0.0;
    cam_y = 0.0;
    cam_h = 0.0;
    cam_angle = std.math.pi / 2.0;

    for (items) |*item| {
        spawnItem(item);
    }
}

fn spawnItem(item: *Item) void {
    const level = levels[level_index];
    if (level_item_index == level.items.len) {
        // make the item "invisible"
        item.y = 1000.0;
        return;
    }

    const level_item = level.items[level_item_index];
    item.x = level_item.x;
    item.y = level_item.y;
    item.h = level_item.h;
    item.kind = level_item.kind;

    level_item_index += 1;
    level_spawn_y = level_item.y;
}

fn drawTime(time: f32, x: i32, y: i32) void {
    const seconds = @floatToInt(u32, time);
    const millis = @floatToInt(u32, @mod(time, 1.0) * 100.0);
    drawNumberText(seconds, x + 24, y);
    w4.text("\"", x + 31, y);
    drawNumberText(millis, x + 48, y);
}

fn drawNumberText(val: u32, x: i32, y: i32) void {
    var x_offset = x;
    var cur_val = val;
    while (true) {
        const print_val = @truncate(u8, cur_val % 10);
        cur_val /= 10;
        w4.text(&[_]u8{'0' + print_val}, x_offset, y);
        x_offset -= font_glyph_width;

        if (cur_val == 0) {
            break;
        }
    }

    if (val < 10) {
        w4.text("0", x_offset, y);
    }
}

fn drawSelIcon(x: i32, y: i32) void {
    const anim_state = (frame % 48) / 16;
    w4.blitSub(&data.stars, x, y - 1, 8, 8, anim_state * 8, 0, data.stars_width, data.stars_flags);
}

fn getGroundPixel(x_ratio: f32, y_ratio: f32) u2 {
    const x = @floatToInt(usize, x_ratio * @as(f32, ground_size));
    const y = @floatToInt(usize, y_ratio * @as(f32, ground_size));

    const index = (y * ground_size + x) >> 2;
    // account for endianness
    const offset = 6 - @truncate(u3, (x & 0b11) << 1);
    const mask = (@as(u8, 0b11) << offset);

    return @truncate(u2, (levels[level_index].ground[index] & mask) >> offset);
}

fn setFramebufferPixel(x: usize, y: usize, color: u2) void {
    if (x >= 0 and x < w4.SCREEN_SIZE and y >= 0 and y < w4.SCREEN_SIZE) {
        const index = (y * w4.SCREEN_SIZE + x) >> 2;
        const offset = @truncate(u3, (x & 0b11) << 1);
        const mask = ~(@as(u8, 0b11) << offset);
        w4.FRAMEBUFFER[index] = (w4.FRAMEBUFFER[index] & mask) | (@as(u8, color) << offset);
    }
}

fn playUiMove() void {
    w4.tone(100 | (150 << 16), 5 | (10 << 8), 15, w4.TONE_PULSE1);
}

fn playUiSelect() void {
    w4.tone(440 | (100 << 16), 5, 30, w4.TONE_PULSE1);
}

fn playRingCollect() void {
    item_collect_frame = frame;
}

fn updatePlayRingCollect() void {
    var play = item_collect_frame > 0;
    var freq: u32 = data.c4;
    switch (frame - item_collect_frame) {
        2 => freq = data.g4,
        4 => freq = data.d5,
        6 => freq = data.g5,
        8 => freq = data.c6,
        else => play = false,
    }

    if (play) {
        w4.tone(freq, 2, 15, w4.TONE_PULSE1);
    }
}

fn playSpeedUpCollect() void {
    const asdr = 5 | (5 << 8) | (10 << 16) | (5 << 24);
    w4.tone(220 | (880 << 16), asdr, 15 | (15 << 8), w4.TONE_PULSE1);
}

fn playRingMiss() void {
    const asdr = 5 | (25 << 8) | (5 << 16) | (5 << 24);
    w4.tone(440 | (880 << 16), asdr, 15 | (15 << 8), w4.TONE_NOISE);
}

fn playCountdownHorn() void {
    const asdr = 15 | (5 << 8) | (1 << 16) | (2 << 24);
    w4.tone(590, asdr, 15 | (15 << 8), w4.TONE_PULSE1);
}

fn playCountdownHornGo() void {
    const asdr = 25 | (5 << 8) | (1 << 16) | (2 << 24);
    w4.tone(1180, asdr, 15 | (15 << 8), w4.TONE_PULSE1);
}

fn playSong(song: *const Song) void {
    song_playing = song;

    initNoteSequenceRuntime(&song_runtime.lead, song.lead);
    initNoteSequenceRuntime(&song_runtime.bass, song.bass);
}

fn initNoteSequenceRuntime(runtime: *NoteSequenceRuntime, sequences: []const NoteSequence) void {
    if (sequences.len == 0) {
        return;
    }

    runtime.beat = 0;
    runtime.repeat_count = sequences[0].repeat;
    runtime.sequence_index = 0;
    runtime.note_index = 0;
}

fn buttonPressed(button: u8) bool {
    return (gamepad & button) != 0;
}

fn buttonPressedThisFrame(button: u8) bool {
    return (gamepad_this_frame & button) != 0 and (gamepad & button) != 0;
}

fn sin(v: f32) f32 {
    var y = v - std.math.tau * @round(v * 1.0 / std.math.tau);

    if (y > 0.5 * std.math.pi) {
        y = std.math.pi - y;
    } else if (y < -std.math.pi * 0.5) {
        y = -std.math.pi - y;
    }
    const y2 = y * y;

    var sinv = @as(f32, -2.3889859e-08) * y2 + 2.7525562e-06;
    sinv = sinv * y2 + -0.00019840874;
    sinv = sinv * y2 + 0.0083333310;
    sinv = sinv * y2 + -0.16666667;
    sinv = sinv * y2 + 1.0;
    return y * sinv;
}

fn cos(v: f32) f32 {
    return sin(v + std.math.pi / 2.0);
}

fn atan(v: f32) f32 {
    const n1 = 0.97239411;
    const n2 = -0.19194795;
    return (n1 + n2 * v * v) * v;
}

fn atan2(y: f32, x: f32) f32 {
    if (x != 0.0) {
        if (@fabs(x) > @fabs(y)) {
            const z = y / x;
            if (x > 0.0) {
                return atan(z);
            } else if (y >= 0.0) {
                return atan(z) + std.math.pi;
            } else {
                return atan(z) - std.math.pi;
            }
        } else {
            const z = x / y;
            if (y > 0.0) {
                return -atan(z) + std.math.pi / 2.0;
            } else {
                return -atan(z) - std.math.pi / 2.0;
            }
        }
    } else {
        if (y > 0.0) {
            return std.math.pi / 2.0;
        } else if (y < 0.0) {
            return -std.math.pi / 2.0;
        }
    }
    return 0.0;
}
