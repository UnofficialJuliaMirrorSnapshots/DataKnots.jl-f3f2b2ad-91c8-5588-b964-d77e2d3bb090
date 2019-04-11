#
# DataKnot definition, integration, and operations.
#

using Tables

import Base:
    convert,
    get,
    show

#
# Definition.
#

"""
    convert(DataKnot, val)

This converter wraps a given value so that it could be used to
start a query.

The unit knot holds the value `nothing`.

```jldoctest
julia> convert(DataKnot, nothing)
│ It │
┼────┼
│    │
```

An empty knot can be constructed with `missing`.

```jldoctest
julia> convert(DataKnot, missing)
│ It │
┼────┼
```

A plural knot is constructed from a vector.

```jldoctest
julia> convert(DataKnot, 'a':'c')
  │ It │
──┼────┼
1 │ a  │
2 │ b  │
3 │ c  │
```

It's often useful to wrap a dataset in a one-field tuple.

```jldoctest
julia> convert(DataKnot, (dataset='a':'c',))
│ dataset │
┼─────────┼
│ a; b; c │
```

---

    get(::DataKnot)

Use `get` to extract the underlying value held by a knot.

```jldoctest
julia> get(convert(DataKnot, "Hello World"))
"Hello World"
```

---

    getindex(::DataKnot, X; kwargs...)

We can query a knot using array indexing notation.

```jldoctest
julia> convert(DataKnot, (dataset='a':'c',))[Count(It.dataset)]
│ It │
┼────┼
│  3 │
```

Query parameters are provided as keyword arguments.

```jldoctest
julia> convert(DataKnot, 1:3)[PWR=2, It .^ It.PWR]
  │ It │
──┼────┼
1 │  1 │
2 │  4 │
3 │  9 │
```
"""
struct DataKnot
    shp::AbstractShape
    cell::AbstractVector

    function DataKnot(shp::AbstractShape, cell::AbstractVector)
        @assert length(cell) == 1
        new(shp, cell)
    end
end

DataKnot(T::Type, cell::AbstractVector) =
    DataKnot(convert(AbstractShape, T), cell)

DataKnot(::Type{Any}, cell::AbstractVector) =
    DataKnot(shapeof(cell), cell)

DataKnot(::Type{Any}, elts::AbstractVector, card::Union{Cardinality,Symbol}) =
    let card = convert(Cardinality, card),
        shp = BlockOf(shapeof(elts), card),
        cell = BlockVector{card}([1, length(elts)+1], elts)
        DataKnot(shp, cell)
    end

convert(::Type{DataKnot}, db::DataKnot) = db

convert(::Type{DataKnot}, ref::Base.RefValue{T}) where {T} =
    DataKnot(ValueOf(T), T[ref.x])

convert(::Type{DataKnot}, elts::AbstractVector) =
    DataKnot(Any, elts, x0toN)

convert(::Type{DataKnot}, ::Missing) =
    DataKnot(Any, Union{}[], x0to1)

convert(::Type{DataKnot}, elt::Union{Tuple, NamedTuple}) =
    DataKnot(Any, [elt])

convert(::Type{DataKnot}, elt) =
    if Tables.schema(elt) !== nothing
        fromtable(elt)
    else
        DataKnot(Any, [elt]);
    end

function DataKnot(ps::Pair{Symbol}...)
    lbls = collect(first.(ps))
    cols = collect(convert.(DataKnot, last.(ps)))
    vals = collect(AbstractVector, cell.(cols))
    shp = TupleOf(lbls, shape.(cols))
    DataKnot(shp, TupleVector(lbls, 1, vals))
end

const unitknot = convert(DataKnot, nothing)

get(db::DataKnot) = db.cell[1]

cell(db::DataKnot) = db.cell

shape(db::DataKnot) = db.shp

quoteof(db::DataKnot) =
    Symbol("DataKnot( … )")

#
# Interfaces.
#

Tables.istable(::Type{<:DataKnot}) = true
Tables.columnaccess(::Type{<:DataKnot}) = true
Tables.schema(knot::DataKnot) = cell_schema(knot.cell)
Tables.columns(knot::DataKnot) = cell_columns(knot.cell)
cell_schema(cell::TupleVector) = etls_schema(cell)
cell_columns(cell::TupleVector) = etls_columns(cell)
cell_schema(cell::AbstractVector) = etls_schema(cell)
cell_columns(cell::AbstractVector) = etls_columns(cell)
cell_schema(cell::BlockVector) = etls_schema(elements(cell))
cell_columns(cell::BlockVector) = etls_columns(elements(cell))
etls_schema(etls::Tables.RowTable) = Tables.schema(etls)
etls_columns(etls::Tables.RowTable) = Tables.columns(etls)
etls_schema(etls::AbstractVector) =
    Tables.Schema((:it,), (typeof(etls[1]),))
etls_columns(etls::AbstractVector) = (it=etls,)
etls_schema(etls::TupleVector) =
    Tables.Schema(labels(etls), eltype.([x for x in columns(etls)]))
etls_columns(etls::TupleVector) =
    NamedTuple{Tuple(labels(etls))}(columns(etls))

function fromtable(table::Any,
                   card::Union{Cardinality, Symbol} = x0toN)
    card = convert(Cardinality, card)
    cols = Tables.columns(table)
    head = Symbol[]
    vals = AbstractVector[]
    for n in propertynames(cols)
        push!(head, n)
        c = getproperty(cols, n)
        push!(vals, c)
    end
    tv = TupleVector(head, length(vals[1]), vals)
    bv = BlockVector([1, length(tv)+1], tv, card)
    return DataKnot(shapeof(bv), bv)
end

#
# Rendering.
#

function show(io::IO, db::DataKnot)
    maxy, maxx = displaysize(io)
    lines = render_dataknot(maxx, maxy, db)
    for line in lines
        println(io, line)
    end
end

function render_dataknot(maxx::Int, maxy::Int, db::DataKnot)
    d = tear_data(table_data(db), maxy)
    l = table_layout(d, maxx)
    c = table_draw(l, maxx)
    return lines!(c)
end

# Mapping data to tabular form.

struct TableData
    head::Array{Tuple{String,Int},2}
    body::TupleVector
    shp::TupleOf
    idxs::AbstractVector{Int}
    tear::Int
end

TableData(head, body, shp) =
    TableData(head, body, shp, 1:0, 0)

TableData(d::TableData; head=nothing, body=nothing, shp=nothing, idxs=nothing, tear=nothing) =
    TableData(head !== nothing ? head : d.head,
              body !== nothing ? body : d.body,
              shp !== nothing ? shp : d.shp,
              idxs !== nothing ? idxs : d.idxs,
              tear !== nothing ? tear : d.tear)

function table_data(db::DataKnot)
    shp = shape(db)
    title = String(getlabel(shp, ""))
    shp = relabel(shp, nothing)
    head = fill((title, 1), (title != "" ? 1 : 0, 1))
    body = TupleVector(1, AbstractVector[cell(db)])
    shp = TupleOf(shp)
    d = TableData(head, body, shp)
    return default_data_header(focus_data(d, 1))
end

focus_data(d::TableData, pos) =
    focus_tuples(focus_blocks(d, pos), pos)

function focus_blocks(d::TableData, pos::Int)
    col_shp = column(d.shp, pos)
    p = as_blocks(col_shp)
    p !== nothing || return d
    blks = chain_of(with_column(pos, p), distribute(pos))(d.body)
    body′ = elements(blks)
    col_shp′ = elements(target(p))
    shp′ = replace_column(d.shp, pos, col_shp′)
    card = cardinality(target(p))
    idxs′ =
        if !isempty(d.idxs)
            elements(chain_of(distribute(2), column(1))(TupleVector(:idxs => d.idxs, :blks => blks)))
        elseif !issingular(card)
            1:length(body′)
        else
            1:0
        end
    TableData(d, body=body′, shp=shp′, idxs=idxs′)
end

as_blocks(::AbstractShape) =
    nothing

as_blocks(src::BlockOf) =
    pass() |> designate(src, src)

as_blocks(src::ValueOf) =
    as_blocks(eltype(src))

as_blocks(::Type) =
    nothing

as_blocks(ity::Type{<:AbstractVector}) =
    adapt_vector() |> designate(ity, BlockOf(eltype(ity)))

as_blocks(ity::Type{>:Missing}) =
    adapt_missing() |> designate(ity, BlockOf(Base.nonmissingtype(ity), x0to1))

function focus_tuples(d::TableData, pos::Int)
    col_shp = column(d.shp, pos)
    p = as_tuples(col_shp)
    p !== nothing || return d
    col′ = p(column(d.body, pos))
    width(col′) > 0 || return d
    cols′ = copy(columns(d.body))
    splice!(cols′, pos:pos, columns(col′))
    body′ = TupleVector(length(d.body), cols′)
    col_shp′ = target(p)
    col_shps′ = copy(columns(d.shp))
    splice!(col_shps′, pos:pos, columns(col_shp′))
    shp′ = TupleOf(col_shps′)
    cw = width(col′)
    hh, hw = size(d.head)
    hh′ = hh + 1
    hw′ = hw + cw - 1
    head′ = fill(("", 0), (hh′, hw′))
    for row = 1:hh
        for col = 1:hw
            col′ = (col <= pos) ? col : col + cw - 1
            (text, span) = d.head[row, col]
            span′ = (col + span - 1 < pos || col > pos) ? span : span + cw - 1
            head′[row, col′] = (text, span′)
        end
    end
    for col = 1:hw
        col′ = (col <= pos) ? col : col + cw - 1
        head′[hh′, col′] = ("", 1)
    end
    for k = 1:cw
        col′ = pos + k - 1
        text = String(label(col_shp′, k))
        head′[hh′, col′] = (text, 1)
    end
    TableData(d, head=head′, body=body′, shp=shp′)
end

as_tuples(::AbstractShape) =
    nothing

as_tuples(src::TupleOf) =
    pass() |> designate(src, src)

as_tuples(src::ValueOf) =
    as_tuples(eltype(src))

as_tuples(::Type) =
    nothing

as_tuples(ity::Type{<:NamedTuple}) =
    adapt_tuple() |> designate(ity,
                               TupleOf(collect(Symbol, ity.parameters[1]),
                                       collect(AbstractShape, ity.parameters[2].parameters)))

as_tuples(ity::Type{<:Tuple}) =
    adapt_tuple() |> designate(ity,
                               TupleOf(collect(AbstractShape, ity.parameters)))

function default_data_header(d::TableData)
    hh, hw = size(d.head)
    hh == 0 && hw > 0 || return d
    head′ = fill(("", 0), (1, hw))
    head′[1, 1] = ("It", hw)
    TableData(d, head=head′)
end

function tear_data(d::TableData, maxy::Int)
    L = length(d.body)
    avail = max(3, maxy - size(d.head, 1) - 4)
    avail < L || return d
    tear = avail ÷ 2
    perm = [1:tear; L-avail+tear+2:L]
    body′ = d.body[perm]
    idxs′ = !isempty(d.idxs) ? d.idxs[perm] : d.idxs
    TableData(d, body=body′, idxs=idxs′, tear=tear)
end

# Rendering table cells.

struct TableCell
    text::String
    align::Int
end

TableCell() = TableCell("", 0)

TableCell(text) = TableCell(text, 0)

struct TableLayout
    cells::Array{TableCell,2}
    sizes::Vector{Tuple{Int,Int}}
    idxs_cols::Int
    head_rows::Int
    tear_row::Int

    TableLayout(w, h, idxs_cols, head_rows, tear_row) =
        new(fill(TableCell(), (h, w)), fill((0, 0), w), idxs_cols, head_rows, tear_row)
end

function table_layout(d::TableData, maxx::Int)
    w = (!isempty(d.idxs)) + width(d.body)
    h = size(d.head, 1) + length(d.body)
    idxs_cols = 0 + (!isempty(d.idxs))
    head_rows = size(d.head, 1)
    tear_row = d.tear > 0 ? head_rows + d.tear : 0
    l = TableLayout(w, h, idxs_cols, head_rows, tear_row)
    populate_body!(d, l, maxx)
    populate_head!(d, l)
    l
end

function populate_body!(d::TableData, l::TableLayout, maxx::Int)
    col = 1
    avail = maxx
    if !isempty(d.idxs)
        avail = populate_column!(l, col, ValueOf(Int), d.idxs, avail)
        col += 1
    end
    for (shp, vals) in zip(columns(d.shp), columns(d.body))
        if avail < 0
            break
        end
        avail = populate_column!(l, col, shp, vals, avail)
        col += 1
    end
end

function populate_column!(l::TableLayout, col::Int, shp::AbstractShape, vals::AbstractVector, avail::Int)
    row = l.head_rows + 1
    sz = 0
    rsz = 0
    for i in eachindex(vals)
        l.cells[row,col] = cell = render_cell(shp, vals, i, avail)
        tw = textwidth(cell.text)
        if cell.align > 0
            rtw = textwidth(cell.text[end-cell.align+2:end])
            ltw = tw - rtw
            lsz = max(sz - rsz, ltw)
            rsz = max(rsz, rtw)
            sz = lsz + rsz
        else
            sz = max(sz, tw)
        end
        row += 1
    end
    l.sizes[col] = (sz, rsz)
    return avail - sz - 2
end

function populate_head!(d::TableData, l::TableLayout)
    for row = size(d.head, 1):-1:1
        for col = 1:size(d.head, 2)
            (text, span) = d.head[row,col]
            if isempty(text)
                continue
            end
            col += l.idxs_cols
            text = escape_string(text)
            l.cells[row,col] = TableCell(text)
            tw = textwidth(text)
            avail = sum(l.sizes[k][1] + 2 for k = col:col+span-1) - 2
            if avail < tw
                extra = 1 + (tw - avail - 1) ÷ span
                k = col
                while avail < tw
                    l.sizes[k] = (l.sizes[k][1] + extra, l.sizes[k][2])
                    avail += extra
                    k += 1
                end
            end
        end
    end
end

function render_cell(shp::TupleOf, vals::AbstractVector, idx::Int, avail::Int, depth::Int=0)
    buf = IOBuffer()
    comma = false
    for i in eachindex(columns(shp))
        if comma
            print(buf, ", ")
            avail -= 2
            comma = false
        end
        cell = render_cell(column(shp, i), column(vals, i), idx, avail, 2)
        print(buf, cell.text)
        avail -= textwidth(cell.text)
        if avail < 0
            break
        end
        if !isempty(cell.text)
            comma = true
        end
    end
    text = String(take!(buf))
    if depth >= 2
        text = "(" * text * ")"
    end
    return TableCell(text)
end

function render_cell(shp::BlockOf, vals::AbstractVector, idx::Int, avail::Int, depth::Int=0)
    offs = offsets(vals)
    elts = elements(vals)
    l = offs[idx]
    r = offs[idx+1]-1
    card = cardinality(shp)
    if issingular(card)
        if l > r
            return depth >= 1 ? TableCell("missing") : TableCell()
        else
            return render_cell(elements(shp), elts, l, avail, depth)
        end
    else
        buf = IOBuffer()
        comma = false
        for k = l:r
            if comma
                print(buf, "; ")
                avail -= 2
                comma = false
            end
            cell = render_cell(elements(shp), elts, k, avail, 1)
            print(buf, cell.text)
            avail -= textwidth(cell.text)
            if avail < 0
                break
            end
            if !isempty(cell.text)
                comma = true
            end
        end
        text = String(take!(buf))
        if depth >= 1
            text = "[" * text * "]"
        end
        return TableCell(text)
    end
end

function render_cell(shp::AbstractShape, vals::AbstractVector, idx::Int, avail::Int, depth::Int=0)
    p = as_blocks(shp)
    p === nothing || return render_cell(target(p), p(vals[idx:idx]), 1, avail, depth)
    p = as_tuples(shp)
    p === nothing || return render_cell(target(p), p(vals[idx:idx]), 1, avail, depth)
    render_cell(vals[idx], avail)
end

function render_value(val)
    buf = IOBuffer()
    io = IOContext(buf, :compact => true, :limit => true)
    print(io, val)
    escape_string(String(take!(buf)))
end

render_cell(val, ::Int) =
    TableCell(render_value(val))

render_cell(::Nothing, ::Int) =
    TableCell("")

render_cell(val::Integer, ::Int) =
    TableCell(render_value(val), 1)

function render_cell(val::Real, ::Int)
    text = render_value(val)
    m = match(r"^(.*?)((?:[\.eE].*)?)$", text)
    alignment = m === nothing ? 1 : length(m.captures[2])+1
    return TableCell(text, alignment)
end

# Serializing table.

struct TableCanvas
    maxx::Int
    maxy::Int
    bufs::Vector{IOBuffer}
    tws::Vector{Int}

    TableCanvas(maxx, maxy) =
        new(maxx, maxy, [IOBuffer() for k = 1:maxy], fill(0, maxy))
end

function write!(c::TableCanvas, x::Int, y::Int, text::String)
    tw = textwidth(text)
    xend = x + tw - 1
    if isempty(text)
        return xend
    end
    @assert 1 <= y <= c.maxy "1 <= $y <= $(c.maxy)"
    @assert c.tws[y] < x "$(c.tws[y]) < $x"
    if x >= c.maxx && c.tws[y] + 1 < c.maxx
        x = c.maxx - 1
        xend = c.maxx
        text = " "
        tw = 1
    end
    if x < c.maxx
        if xend >= c.maxx
            tw = 0
            i = 0
            for i′ in eachindex(text)
                ch = text[i′]
                ctw = textwidth(ch)
                if x + tw + ctw - 1 < c.maxx
                    tw += ctw
                else
                    text = text[1:i]
                    break
                end
                i = i′
            end
            text = text * "…"
            tw += 1
            xend = x + tw - 1
        end
        if x > c.tws[y] + 1
            print(c.bufs[y], " " ^ (x - c.tws[y] - 1))
        end
        print(c.bufs[y], text)
        c.tws[y] = xend
    end
    xend
end

lines!(c::TableCanvas) =
    String.(take!.(c.bufs))

overflow(c::TableCanvas, x::Int) =
    x >= c.maxx

function table_draw(l::TableLayout, maxx::Int)
    maxy = size(l.cells, 1) + (l.tear_row > 0) + 1
    c = TableCanvas(maxx, maxy)
    extent = 0
    for col = 1:size(l.cells, 2)
        if col == l.idxs_cols + 1
            extent = draw_bar!(c, extent, l, l.idxs_cols == 0 ? -1 : 0)
        end
        extent = draw_column!(c, extent, l, col)
        if overflow(c, extent)
            break
        end
    end
    draw_bar!(c, extent, l, 1)
    c
end

function draw_bar!(c::TableCanvas, extent::Int, l::TableLayout, pos::Int)
    x = extent + 1
    y = 1
    for row = 1:size(l.cells, 1)
        write!(c, x, y, "│")
        y += 1
        if row == l.head_rows
            write!(c, x, y, "┼")
            y += 1
        end
        if row == l.tear_row
            y += 1
        end
    end
    extent + 1
end

function draw_column!(c::TableCanvas, extent::Int, l::TableLayout, col::Int)
    sz, rsz = l.sizes[col]
    if col == 1 && l.idxs_cols > 0
        sz -= 1
    end
    y = 1
    for row = 1:size(l.cells, 1)
        x = extent + 2
        cell = l.cells[row, col]
        if !isempty(cell.text)
            if cell.align > 0
                x = extent + sz - rsz - textwidth(cell.text) + cell.align + 1
            end
            write!(c, x, y, cell.text)
        end
        y += 1
        x = extent + 2
        if row == l.head_rows
            write!(c, extent + 1, y, "─" ^ (sz + 2))
            y += 1
        end
        if row == l.tear_row
            if col == 1
                write!(c, x + sz - 1, y, "⋮")
            end
            y += 1
        end
    end
    extent + sz + 2
end
