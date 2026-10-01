--!strict
-- Minimal Signal implementation (no RBXScriptSignal required).

export type Connection = {
    Disconnect: (self: Connection) -> (),
    Connected: boolean,
}

export type Signal<T...> = {
    Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
    Fire: (self: Signal<T...>, T...) -> (),
    Destroy: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
    local self = setmetatable({}, Signal)
    self._handlers = {}
    self._destroyed = false
    return (self :: any) :: Signal<T...>
end

function Signal:Connect(callback)
    assert(not self._destroyed, "Signal is destroyed")
    assert(type(callback) == "function", "callback must be a function")

    local handler = {
        callback = callback,
        connected = true,
    }

    table.insert(self._handlers, handler)

    local connection = {}
    connection.Connected = true

    function connection:Disconnect()
        if not connection.Connected then
            return
        end
        connection.Connected = false
        handler.connected = false
    end

    return connection
end

function Signal:Fire(...)
    if self._destroyed then
        return
    end

    for _, handler in ipairs(self._handlers) do
        if handler.connected then
            handler.callback(...)
        end
    end
end

function Signal:Destroy()
    self._destroyed = true
    self._handlers = {}
end

return Signal
