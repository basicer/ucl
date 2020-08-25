include_files = {'*.lua', 'ucl/*.lua'}
exclude_files = {'out.lua'}

ignore = {
    '212/interp',
    '212/self',
    '211/ValueType_.*',
    '211/ReturnCode_.*',
    '542',
    '432/self',
    '511'
}

files["pack.lua"] = {ignore = {"613"}}