--!strict
-- Simple cleanup helper.

export type Task = RBXScriptConnection | Instance | (() -> ()) | thread

export type Maid = {
    GiveTask: (self: Maid, task: Task) -> Task,
    DoCleaning: (self: Maid) -> (),
}

local Maid = {}
Maid.__index = Maid

function Maid.new(): Maid
    local self = setmetatable({}, Maid)
    self._tasks = {}
    return (self :: any) :: Maid
end

function Maid:GiveTask(task: Task): Task
    table.insert(self._tasks, task)
    return task
end

local function clean_task(task: Task)
    if typeof(task) == "RBXScriptConnection" then
        task:Disconnect()
        return
    end

    if typeof(task) == "Instance" then
        task:Destroy()
        return
    end

    if type(task) == "function" then
        task()
        return
    end

    if type(task) == "thread" then
        task.cancel(task)
        return
    end
end

function Maid:DoCleaning()
    for _, task_item in ipairs(self._tasks) do
        clean_task(task_item)
    end
    self._tasks = {}
end

return Maid
