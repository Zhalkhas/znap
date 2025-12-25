const std = @import("std");
const Stream = std.net.Stream;

const event_stream_cmd = "\"EventStream\"\n";

pub fn run(listen_stream: Stream, cmd_stream: Stream) !void {
    const alloc = std.heap.page_allocator;

    std.debug.print("connected to Niri socket\n", .{});

    const read_buffer: []u8 = try alloc.alloc(u8, 4096);
    defer alloc.free(read_buffer);

    var r = listen_stream.reader(read_buffer);
    var io_r: *std.Io.Reader = r.interface();

    var w = listen_stream.writer(&.{});
    var io_w: *std.Io.Writer = &w.interface;

    std.debug.print("sending EventStream command\n", .{});

    _ = try io_w.write(event_stream_cmd);
    try io_w.flush();

    var floating_window_ids = std.AutoHashMap(u32, struct {}).init(alloc);

    var cmd_w = cmd_stream.writer(&.{});
    var io_cmd_w = &cmd_w.interface;

    const cmd_read_buffer: []u8 = try alloc.alloc(u8, 4096);
    defer alloc.free(cmd_read_buffer);
    var cmd_r = cmd_stream.reader(cmd_read_buffer);
    var io_cmd_r: *std.Io.Reader = cmd_r.interface();

    std.debug.print("listening events:\n", .{});

    while (true) {
        const line = try io_r.takeDelimiter('\n') orelse &.{};
        if (line.len == 0) {
            continue;
        }
        std.debug.print("read line: {s}\n", .{line});

        const json: std.json.Parsed(Event) = std.json.parseFromSlice(
            Event,
            alloc,
            line,
            .{ .ignore_unknown_fields = true },
        ) catch |err| {
            std.debug.print("failed to parse JSON: {any}\n", .{err});
            continue;
        };

        std.debug.print("parsed JSON: {any}\n", .{json.value});

        if (json.value.WindowOpenedOrChanged) |event| {
            if (event.window.is_floating and std.mem.eql(u8, event.window.title, "Picture-in-Picture")) {
                try floating_window_ids.put(event.window.id, .{});
            }
        }
        if (json.value.WorkspaceActivated) |event| {
            if (event.focused) {
                var iter = floating_window_ids.keyIterator();
                while (iter.next()) |window_id| {
                    std.debug.print("sending command to move floating window {d} to workspace {d}\n", .{ window_id.*, event.id });

                    const formatter = std.json.fmt(
                        ChangeWorkspaceAction().init(window_id.*, event.id),
                        .{ .whitespace = .minified },
                    );
                    try formatter.format(io_cmd_w);
                    _ = try io_cmd_w.write("\n");
                    try io_cmd_w.flush();

                    const response = try io_cmd_r.takeDelimiterExclusive('\n');
                    if (!std.mem.eql(u8, response, "{\"Ok\":\"Handled\"}")) {
                        std.log.warn("Unexpected response from Niri: {s}", .{response});
                    }
                    std.debug.print("Response from Niri: {s}\n", .{response});
                }
            }
        }
        if (json.value.WindowClosed) |event| {
            _ = floating_window_ids.remove(event.id);
        }

        json.deinit();
    }
}

fn ChangeWorkspaceAction() type {
    return struct {
        Action: struct {
            MoveWindowToWorkspace: struct {
                window_id: u32,
                reference: struct {
                    Id: u32,
                },
                focus: bool,
            },
        },
        pub fn init(window_id: u32, workspace_id: u32) @This() {
            return .{
                .Action = .{
                    .MoveWindowToWorkspace = .{
                        .window_id = window_id,
                        .reference = .{
                            .Id = workspace_id,
                        },
                        .focus = false,
                    },
                },
            };
        }
    };
}

const workspace_change_event =
    \\{"WorkspaceActivated":{"id":2,"focused":true}} 
;
const floating_window_opened_event =
    \\{
    \\  "WindowOpenedOrChanged": {
    \\    "window": {
    \\      "id": 10,
    \\      "title": "Picture-in-Picture",
    \\      "app_id": "librewolf",
    \\      "pid": 4738,
    \\      "workspace_id": 2,
    \\      "is_focused": true,
    \\      "is_floating": true,
    \\      "is_urgent": false,
    \\      "layout": {
    \\        "pos_in_scrolling_layout": null,
    \\        "tile_size": [
    \\          512,
    \\          288
    \\        ],
    \\        "window_size": [
    \\          512,
    \\          288
    \\        ],
    \\        "tile_pos_in_workspace_view": [
    \\          704,
    \\          418
    \\        ],
    \\        "window_offset_in_tile": [
    \\          0,
    \\          0
    \\        ]
    \\      }
    \\    }
    \\  }
    \\}
;
const floating_window_closed_event =
    \\{"WindowClosed":{"id":12}}
;

const ignored_events =
    \\ {"Ok":"Handled"}
    \\ {"WindowsChanged":{"windows":[{"id":4,"title":"root.zig - znap - Visual Studio Code","app_id":"code","pid":5635,"workspace_id":1,"is_focused":true,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[1,1],"tile_size":[1836.0,1016.0],"window_size":[1836,1016],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]}},{"id":8,"title":"~","app_id":"com.mitchellh.ghostty","pid":186157,"workspace_id":2,"is_focused":false,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[3,1],"tile_size":[913.0,1016.0],"window_size":[913,1016],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]}},{"id":3,"title":"Unions | zig.guide — LibreWolf","app_id":"librewolf","pid":4738,"workspace_id":1,"is_focused":false,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[2,1],"tile_size":[1836.0,1016.0],"window_size":[1836,1016],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]}},{"id":2,"title":"Грехо Обзор Громовержцы (Кино обзор) - YouTube — LibreWolf","app_id":"librewolf","pid":4738,"workspace_id":2,"is_focused":false,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[1,1],"tile_size":[913.0,1016.0],"window_size":[913,1016],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]}},{"id":9,"title":"Тимлид не кодит – (37)","app_id":"org.telegram.desktop","pid":6422,"workspace_id":2,"is_focused":false,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[2,1],"tile_size":[913.0,1016.0],"window_size":[913,1016],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]}}]}}
    \\ {"KeyboardLayoutsChanged":{"keyboard_layouts":{"names":["English (US)","Kazakh"],"current_idx":0}}}
    \\ {"OverviewOpenedOrClosed":{"is_open":false}}
    \\ {"ConfigLoaded":{"failed":false}}
    \\ {"WindowOpenedOrChanged":{"window":{"id":4,"title":"root.zig - znap - Visual Studio Code","app_id":"code","pid":5635,"workspace_id":1,"is_focused":true,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[1,1],"tile_size":[1836.0,1016.0],"window_size":[1836,1016],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]}}}}
;

const Event = struct {
    WorkspaceActivated: ?struct {
        id: u32,
        focused: bool,
    } = null,
    WindowOpenedOrChanged: ?struct {
        window: struct {
            id: u32,
            title: []const u8,
            app_id: []const u8,
            pid: u32,
            workspace_id: u32,
            is_focused: bool,
            is_floating: bool,
            is_urgent: bool,
            layout: struct {
                pos_in_scrolling_layout: ?[]const u8,
                tile_size: [2]u32,
                window_size: [2]u32,
                tile_pos_in_workspace_view: [2]u32,
                window_offset_in_tile: [2]u32,
            },
        },
    } = null,
    WindowClosed: ?struct {
        id: u32,
    } = null,
};

test "parse window opened or changed event" {
    const alloc = std.testing.allocator;
    const json = std.json.parseFromSlice(Event, alloc, floating_window_opened_event, .{ .ignore_unknown_fields = true }) catch |err| {
        std.debug.print("failed to parse JSON: {any}\n", .{err});
        unreachable;
    };
    defer json.deinit();

    try std.testing.expectEqualDeep(Event{
        .WindowOpenedOrChanged = .{
            .window = .{
                .id = 10,
                .title = "Picture-in-Picture",
                .app_id = "librewolf",
                .pid = 4738,
                .workspace_id = 2,
                .is_focused = true,
                .is_floating = true,
                .is_urgent = false,
                .layout = .{
                    .pos_in_scrolling_layout = null,
                    .tile_size = .{ 512, 288 },
                    .window_size = .{ 512, 288 },
                    .tile_pos_in_workspace_view = .{ 704, 418 },
                    .window_offset_in_tile = .{ 0, 0 },
                },
            },
        },
    }, json.value);
}

test "parse workspace change event" {
    const alloc = std.testing.allocator;
    const json = std.json.parseFromSlice(Event, alloc, workspace_change_event, .{ .ignore_unknown_fields = true }) catch |err| {
        std.debug.print("failed to parse JSON: {any}\n", .{err});
        unreachable;
    };
    defer json.deinit();

    try std.testing.expectEqual(Event{
        .WorkspaceActivated = .{
            .id = 2,
            .focused = true,
        },
    }, json.value);
}

test "parse window closed event" {
    const alloc = std.testing.allocator;
    const json = std.json.parseFromSlice(Event, alloc, floating_window_closed_event, .{ .ignore_unknown_fields = true }) catch |err| {
        std.debug.print("failed to parse JSON: {any}\n", .{err});
        unreachable;
    };
    defer json.deinit();

    try std.testing.expectEqual(Event{
        .WindowClosed = .{
            .id = 12,
        },
    }, json.value);
}

test "parsing ignored events does not fail" {
    const alloc = std.testing.allocator;

    var events = std.mem.splitSequence(u8, ignored_events, "\n");
    while (events.next()) |event_str| {
        const json = std.json.parseFromSlice(Event, alloc, event_str, .{ .ignore_unknown_fields = true }) catch |err| {
            std.debug.print("failed to parse JSON: {any}\n", .{err});
            unreachable;
        };
        defer json.deinit();
    }
}
