export numcells
export numvertices, dimension, vertices, coordtype
export meshsegment, meshrectangle, meshcircle, meshsphere
export readmesh, writemesh, boundary, vertextocellmap, cells, connectivity, buildvolmpairs
export relorientation, universedimension, meshfromfile
export translate, translate!
export Mesh

#abstract AbstractMesh{T}
#valuetype{T}(m::AbstractMesh{T}) = T

# P is the point type supporting eltype(P) and length(P)
# C is the index type supporting length(C)
type Mesh{U,D1,T} #<: AbstractMesh{T}
    vertices::Vector{Vec{U,T}}
    faces::Vector{Vec{D1,Int}}
end



export emptymesh
"""
    emptymesh(type, mdim, udim=mdim+1)

Returns an empty mesh with `coordtype` equal to `type`, of dimension `mdim`
and embedded in a universe of dimension `udim`
"""
emptymesh(T, mdim, udim=mdim+1) = Mesh(Pt{udim,T}[], Vec{mdim+1,Int}[])



vertextype(m::Mesh) = eltype(m.vertices)
indextype(m::Mesh) = eltype(m.faces)
coordtype(m::Mesh) = eltype(vertextype(m))

dimension(m::Mesh) = length(indextype(m)) - 1
universedimension(m::Mesh) = length(vertextype(m))

vertices(m::Mesh) = m.vertices
vertices(m::Mesh, I) = m.vertices[I]

numvertices(m::Mesh) = length(m.vertices)
numcells(m::Mesh) = length(m.faces)

translate(Γ::Mesh, v) = Mesh(Γ.vertices+v, Γ.faces)
function translate!(Γ::Mesh, v)
    for i in 1:length(Γ.vertices)
        Γ.vertices[i] += v
    end
    Γ
end

function meshfromfile(filename)
    open(filename) do f
        # multi-mesh files are not supported
        readline(f)

        # read the number of vertices and faces
        l = readline(f)

        sl = split(l)
        num_vertices = parse(Int, sl[1])
        num_faces    = parse(Int, sl[2])

        # TODO: remove explicit reference to 3D
        T = Float64
        P = Vec{3,T}
        vertices = zeros(P, num_vertices)
        for i = 1 : num_vertices
            l = readline(f)
            vertices[i] = Point(float(split(l)))
        end

        # TODO: remove explicit reference to dimension
        C = Vec{3,Int}
        faces = zeros(C, num_faces)
        for i in 1 : num_faces
            l = readline(f)
            faces[i] = Vec([parse(Int,s) for s in split(l)])
        end

        Mesh(vertices, faces)
    end
end

function writemesh(mesh, filename)
    dl = '\t'
    open(filename, "w") do f
        println(f, 1)
        println(f, numvertices(mesh), dl, numcells(mesh))
        for v in mesh.vertices
            println(f, v[1], dl, v[2], dl, v[3])
        end
        for c in mesh.faces
            println(f, c[1], dl, c[2], dl, c[3])
        end
    end
end

"""
function to determine the boundary of a manifold.
Given a D-manifold, return a D-1 manifold representing
the boundary and a array containing the indices of the
vertices of the original mesh that corresond to he
vertices of the boundary mesh.
"""
function boundary(mesh)

    D = dimension(mesh)

    # vertices have no boundary
    @assert 0 < D

    # build a list of D-1 cells
    edges = cells(mesh, D-1)
    faces = cells(mesh, D)

    # get the edge-face connection matrix
    conn = connectivity(mesh, D-1, edges, faces)

    # find the edges that only have one edjacent face
    i = find(x -> x < 2, sum(abs(conn), 1))

    # create a mesh out of these
    bnd = Mesh(mesh.vertices, edges.faces[i])
end

"""
    vertextocellmap(mesh::Mesh)

This function takes an array of indices into the mesh vertex buffer
representing cells of a fixed dimension and returns an array of size
numvertices(mesh) x nmax integers containing in row i the indices
of the cells containing the i-th vertex. In addition the function returns
an array of length numvertices(mesh) containing the number of cells each
vertex is a member of.
"""
#function vertextocellmap(mesh::Mesh, cells=mesh.faces)
function vertextocellmap(mesh)

    cells = mesh.faces

    numverts = numvertices(mesh)
    numcells = length(cells)
    numneighbors = zeros(Int, numverts)
    for i = 1 : numcells
        numneighbors[ cells[i] ] += 1
    end

    npos = -1
    vertstocells = fill(npos, numverts, maximum(numneighbors))
    numneighbors = zeros(Int, numverts)
    for i = 1 : numcells
        cell = cells[i]
        for j = 1 : length(cell)
            #v = cells[j,i]
            v = cell[j]
            k = (numneighbors[v] += 1)
            vertstocells[v,k] = i
        end
    end

    vertstocells, numneighbors
end

"""
Returns the cells of dimension k as an integer array of size k x N where N
is the number of cells of dimension k. The integers in this array represent
indices into the vertex buffer of the input mesh. Note that for the special
case k == 0 this function does not return any floating vertices.
"""
function cells(mesh, dim::Integer)

    meshdim = dimension(mesh)
    @assert 0 <= dim <= meshdim

    if dim == meshdim
        return mesh
    end

    #C = celltype(mesh)
    nc = numcells(mesh)
    C = Vec{dim+1,Int}
    simplices = zeros(C, nc*binomial(meshdim+1,dim+1))

    n = 1
    for c = 1 : nc

        cell = mesh.faces[c]
        for simplex in combinations(cell,dim+1)
            simplices[n] = sort(simplex)
            n += 1
        end
    end

    simplices = unique(simplices)
    Mesh(mesh.vertices, simplices)
end



function cells(pred, mesh, dim)

    meshdim = dimension(mesh)
    @assert 0 <= dim <= meshdim

    C = celltype(mesh)
    nc = numcells(mesh)
    simplices = zeros(C, nc*binomial(meshdim+1,dim+1))

    n = 1
    for c = 1 : nc

        cell = mesh.faces[c]
        for simplex in combinations(cell,dim+1)
            if pred(Vec{dim+1,Int}(simplex))
                simplices[n] = sort(simplex)
                n += 1
            end
        end
    end

    simplices = simplices[1:n-1]
    simplices = unique(simplices)

    Mesh(mesh.vertices, simplices)
end


function findfirst{T}(A, V::Array{T,1})
    I = zeros(Int, length(V))
    for (k,v) in enumerate(V)
        I[k] = Base.findfirst(A, v)
    end
    return I
end

function findfirst{N,T}(A, V::Vec{N,T})
    I = zeros(Int, length(V))
    for (k,v) in enumerate(V)
        I[k] = Base.findfirst(A, v)
    end
    return I
end




const levicivita_lut = cat(3,
    [0 0  0;  0 0 1; 0 -1 0],
    [0 0 -1;  0 0 0; 1  0 0],
    [0 1  0; -1 0 0; 0  0 0])

# Levi-Civita symbol of a permutation.
# The parity is computed by using the fact that a permutation is odd if and
# only if the number of even-length cycles is odd.
# Returns 1 is the permutarion is even, -1 if it is odd and 0 otherwise.
function levicivita(p)
    n = length(p)

    if n == 3
        @inbounds valid = (0 < p[1] <= 3) * (0 < p[2] <= 3) * (0 < p[3] <= 3)
        return valid ? levicivita_lut[p[1], p[2], p[3]] : 0
    end

    todo = trues(n)
    first = 1
    cycles = flips = 0

    while cycles + flips < n
        first = findnext(todo, first)
        (todo[first] $= true) && return 0
        j = p[first]
        (0 < j <= n) || return 0
        cycles += 1
        while j ≠ first
            (todo[j] $= true) && return 0
            j = p[j]
            (0 < j <= n) || return 0
            flips += 1
        end
    end

    return iseven(flips) ? 1 : -1
end

# given a simplex and a face returns:
# +v if face is the v-th face of the simplex oriented according to the simplex
# -v if face is the v-th face of the simplex oriented oppositely to the simplex
# 0 is face is not a face of the simplex
function relorientation(face, simplex)

    v = setdiff(simplex, face)
    if length(v) != 1
        return 0
    end

    # find the position of the missing vertex
    v = v[1]
    i = Base.findfirst(simplex, v)
    s = (-1)^(i-1)

    # remove that vertex from the simplex
    face2 = Array(Int, length(simplex)-1)
    for j in 1 : i-1
        face2[j] = simplex[j]
    end
    for j in i : length(simplex)-1
        face2[j] = simplex[j+1]
    end
    #face2 = [ simplex[1:i-1]; simplex[i+1:end]]

    # get the permutation that maps face to face2
    p = findfirst(face2,face)

    return s * levicivita(p) * i
end

"""
    connectivity(mesh::Mesh, k, kcells, mcells)

Computes a dimm x dimk sparse matrix D with D[i,j] = +/-1 if m-cell i
has k-cell j as a face. The sign depends on the relative orientation.
"""
function connectivity(mesh, k, kcells, mcells; op = sign)

    if !( -1 <= k <= dimension(mesh))
        throw(ErrorException("k needs to be between zero and dim(mesh)"))
    end

    if k == -1
        return zeros(Int, numvertices(mesh), 0)
    end

    if k == dimension(mesh)
        return zeros(Int, 0, numcells(mesh))
    end

    vtok, _ = vertextocellmap(kcells)
    vtom, _ = vertextocellmap(mcells)

    const npos = -1

    dimk = numcells(kcells)
    dimm = numcells(mcells)

    D = spzeros(Int, dimm, dimk)

    for v in 1 : numvertices(mesh)
        for i in vtok[v,:]
            i == npos && break
            kcell = kcells.faces[i]
            for j in vtom[v,:]
                j == npos && break
                mcell = mcells.faces[j]
                relo = relorientation(kcell, mcell)
                D[j,i] = op(relo)
            end
        end
    end

    return D

end

"""
create pairs of volume cells from hypercells
and the assumption of global orientation
Every column of the returned array is a pair of indices
If both ids are positive then they both refer to faces
in the mesh structure. If the second number `id` is negative, this
means that the coresponding edge lies on the boundary and that
this edge has local index `-id` in the cell refererred to by the first index
"""
function buildvolmpairs(mesh, edges)

    @assert dimension(edges)+1 == dimension(mesh)

    numedges = numcells(edges)
    facepairs = zeros(Int, 2, numedges)

    v2e, nn = vertextocellmap(mesh)
    for e in 1:numedges

        edge = edges.faces[e]

        # neighborhood of startvertex
        v = edge[1]
        n = nn[v]
        nbd1 = v2e[v,1:n]

        # neighborhood of endvertex
        v = edge[2]
        n = nn[v]
        nbd2 = v2e[v,1:n]

        # get the intersection
        nbd = intersect(nbd1, nbd2)

        n = length(nbd)
        @assert 0 <= n <= 2
        if n == 1 # boundary edge
            c = nbd[1]
            cell = mesh.faces[c]
            s = relorientation(edge, cell)
            facepairs[1,e] = c
            facepairs[2,e] = -abs(s)
        else # internal edge
            k = 0
            for c in nbd
                cell = mesh.faces[c]
                s = relorientation(edge, cell)
                if s > 0
                    facepairs[1,e] = c
                else
                    facepairs[2,e] = c
                end
            end
        end
    end

    facepairs

end
