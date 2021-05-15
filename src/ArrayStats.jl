## --- Transformations of arrays with NaNs

    function possiblydropdims(A, drop::Bool, dims)
        if drop
            if ndims(A) > 1 && size(A,dims)==1
                return dropdims(A,dims=dims)
            end
        else
            return A
        end
    end
    function possiblydropdims(A, drop::Bool, ::Colon)
        return A
    end

    """
    ```julia
    nanmask(A)
    ```
    Create a Boolean mask of dimensions `size(A)` that is false wherever `A` is `NaN`
    """
    nanmask(A) = nanmask!(Array{Bool}(undef,size(A)), A)
    export nanmask

    """
    ```julia
    nanmask!(mask, A)
    ```
    Fill a Boolean mask of dimensions `size(A)` that is false wherever `A` is `NaN`
    """
    function nanmask!(mask, A)
        @avx for i=1:length(A)
            mask[i] = A[i]==A[i]
        end
        return mask
    end
    # Special methods for arrays that cannot contain NaNs
    nanmask!(mask, A::AbstractArray{<:Integer}) = fill!(mask, true)
    nanmask!(mask, A::AbstractArray{<:Rational}) = fill!(mask, true)

    """
    ```julia
    zeronan!(A)
    ```
    Replace all `NaN`s in A with zeros of the same type
    """
    function zeronan!(A::Array)
        @avx for i ∈ eachindex(A)
            Aᵢ = A[i]
            A[i] = ifelse(Aᵢ==Aᵢ, Aᵢ, 0)
        end
        return A
    end
    export zeronan!


## --- Min & max ignoring NaNs

    """
    ```julia
    nanmax(a,b)
    ```
    As `max(a,b)`, but if either argument is `NaN`, return the other one
    """
    nanmax(a, b) = ifelse(a > b, a, b)
    nanmax(a, b::AbstractFloat) = ifelse(a==a, ifelse(b > a, b, a), b)
    nanmax(a, b::Vec{N,<:AbstractFloat}) where N = ifelse(a==a, ifelse(b > a, b, a), b)
    export nanmax

    """
    ```julia
    nanmin(a,b)
    ```
    As `min(a,b)`, but if either argument is `NaN`, return the other one
    """
    nanmin(a, b) = ifelse(a < b, a, b)
    nanmin(a, b::AbstractFloat) = ifelse(a==a, ifelse(b < a, b, a), b)
    nanmin(a, b::Vec{N,<:AbstractFloat}) where N = ifelse(a==a, ifelse(b < a, b, a), b)
    export nanmin

## --- Percentile statistics, excluding NaNs

    """
    ```julia
    nanpctile(A, p; dims)
    ```
    Find the `p`th percentile of an indexable collection `A`, ignoring NaNs,
    optionally along a dimension specified by `dims`.

    A valid percentile value must satisfy 0 <= `p` <= 100.
    """
    nanpctile(A, p; dims=:, drop=false) = possiblydropdims(_nanpctile(A, p, dims), drop, dims)
    function _nanpctile(A, p, ::Colon)
        t = nanmask(A)
        return any(t) ? percentile(A[t],p) : NaN
    end
    function _nanpctile(A, p, region)
        s = size(A)
        if region == 2
            t = Array{Bool}(undef, s[2])
            result = Array{float(eltype(A))}(undef, s[1], 1)
            for i=1:s[1]
                nanmask!(t, A[i,:])
                result[i] = any(t) ? percentile(A[i,t],p) : NaN
            end
        elseif region == 1
            t = Array{Bool}(undef, s[1])
            result = Array{float(eltype(A))}(undef, 1, s[2])
            for i=1:s[2]
                nanmask!(t, A[:,i])
                result[i] = any(t) ? percentile(A[t,i],p) : NaN
            end
        else
            result = _nanpctile(A, p, :)
        end
        return result
    end
    export nanpctile


    """
    ```julia
    inpctile(A, p::Number; dims)
    ```
    Return a boolean array that identifies which values of the iterable
    collection `A` fall within the central `p`th percentile, optionally along a
    dimension specified by `dims`.

    A valid percentile value must satisfy 0 <= `p` <= 100.
    """
    function inpctile(A, p)
        offset = (100 - p) / 2
        return _nanpctile(A, offset, :) .< A .< _nanpctile(A, 100-offset, :)
    end
    export inpctile

## --- Combine arrays containing NaNs

    """
    ```julia
    nanadd(A, B)
    ```
    Add the non-NaN elements of A and B, treating NaNs as zeros
    """
    nanadd(a,b) = ifelse(a==a, a, zero(typeof(a))) + ifelse(b==b, b, zero(typeof(b)))
    function nanadd(A::AbstractArray, B::AbstractArray)
        result_type = promote_type(eltype(A), eltype(B))
        result = similar(A, result_type)
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            Bᵢ = B[i]
            result[i] = (Aᵢ * (Aᵢ==Aᵢ)) + (Bᵢ * (Bᵢ==Bᵢ))
        end
        return result
    end
    export nanadd

    """
    ```julia
    nanadd!(A, B)
    ```
    Add the non-NaN elements of `B` to `A`, treating NaNs as zeros
    """
    function nanadd!(A::Array, B::AbstractArray)
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            Bᵢ = B[i]
            A[i] = (Aᵢ * (Aᵢ==Aᵢ)) + (Bᵢ * (Bᵢ==Bᵢ))
        end
        return A
    end
    export nanadd!


## --- Summary statistics of arrays with NaNs

    """
    ```julia
    nansum(A; dims)
    ```
    Calculate the sum of an indexable collection `A`, ignoring NaNs, optionally
    along dimensions specified by `dims`.
    """
    nansum(A; dims=:, drop=false) = possiblydropdims(_nansum(A, dims), drop, dims)
    _nansum(A, region) = sum(A.*nanmask(A), dims=region)
    function _nansum(A,::Colon)
        m = zero(eltype(A))
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            m += Aᵢ * (Aᵢ==Aᵢ)
        end
        return m
    end
    function _nansum(A::Array,::Colon)
        T = eltype(A)
        m = zero(T)
        @avx for i ∈ eachindex(A)
            Aᵢ = A[i]
            m += ifelse(Aᵢ==Aᵢ, Aᵢ, zero(T))
        end
        return m
    end
    function _nansum(A::Array{<:Integer},::Colon)
        m = zero(eltype(A))
        @avx for i ∈ eachindex(A)
            m += A[i]
        end
        return m
    end
    export nansum

    """
    ```julia
    nanminimum(A; dims)
    ```
    As `minimum` but ignoring `NaN`s: Find the smallest non-`NaN` value of an
    indexable collection `A`, optionally along a dimension specified by `dims`.
    """
    nanminimum(A; dims=:, drop=false) = possiblydropdims(_nanminimum(A, dims), drop, dims)
    _nanminimum(A, region) = reduce(nanmin, A, dims=region, init=float(eltype(A))(NaN))
    _nanminimum(A::Array{<:Number}, ::Colon) = vreduce(nanmin, A)
    export nanminimum


    """
    ```julia
    nanmaximum(A; dims)
    ```
    Find the largest non-NaN value of an indexable collection `A`, optionally
    along a dimension specified by `dims`.
    """
    nanmaximum(A; dims=:, drop=false) = possiblydropdims(_nanmaximum(A, dims), drop, dims)
    _nanmaximum(A, region) = reduce(nanmax, A, dims=region, init=float(eltype(A))(NaN))
    _nanmaximum(A::Array{<:Number}, ::Colon) = vreduce(nanmax, A)
    export nanmaximum


    """
    ```julia
    nanextrema(A; dims)
    ```
    Find the extrema (maximum & minimum) of an indexable collection `A`,
    ignoring NaNs, optionally along a dimension specified by `dims`.
    """
    nanextrema(A; dims=:, drop=false) = possiblydropdims(_nanextrema(A, dims), drop, dims)
    _nanextrema(A, region) = collect(zip(_nanminimum(A, region), _nanmaximum(A, region)))
    _nanextrema(A, ::Colon) = (_nanminimum(A, :), _nanmaximum(A, :))
    export nanextrema


    """
    ```julia
    nanrange(A; dims)
    ```
    Calculate the range (maximum - minimum) of an indexable collection `A`,
    ignoring NaNs, optionally along a dimension specified by `dims`.
    """
    nanrange(A; dims=:, drop=false) = possiblydropdims(_nanmaximum(A, dims) - _nanminimum(A, dims), drop, dims)
    export nanrange


    """
    ```julia
    nanmean(A, [W]; dims)
    ```
    Ignoring NaNs, calculate the mean (optionally weighted) of an indexable
    collection `A`, optionally along dimensions specified by `dims`.
    """
    nanmean(A; dims=:, drop=false) = possiblydropdims(_nanmean(A, dims), drop, dims)
    function _nanmean(A, region)
        mask = nanmask(A)
        return sum(A.*mask, dims=region) ./ sum(mask, dims=region)
    end
    # Fallback method for non-Arrays
    function _nanmean(A, ::Colon)
        n = 0
        m = zero(eltype(A))
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            t = Aᵢ == Aᵢ
            n += t
            m += Aᵢ * t
        end
        return m / n
    end
    # Can't have NaNs if array is all Integers
    function _nanmean(A::Array{<:Integer}, ::Colon)
        m = zero(eltype(A))
        @avx for i ∈ eachindex(A)
            m += A[i]
        end
        return m / length(A)
    end
    # Optimized AVX version for floats
    function _nanmean(A::AbstractArray{<:AbstractFloat}, ::Colon)
        n = 0
        T = eltype(A)
        m = zero(T)
        @avx for i ∈ eachindex(A)
            Aᵢ = A[i]
            t = Aᵢ==Aᵢ
            n += t
            m += ifelse(t, Aᵢ, zero(T))
        end
        return m / n
    end

    nanmean(A, W; dims=:, drop=false) = possiblydropdims(_nanmean(A, W, dims), drop, dims)
    function _nanmean(A, W, region)
        mask = nanmask(A)
        return sum(A.*W.*mask, dims=region) ./ sum(W.*mask, dims=region)
    end
    # Fallback method for non-Arrays
    function _nanmean(A, W, ::Colon)
        n = zero(eltype(W))
        m = zero(promote_type(eltype(W), eltype(A)))
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            Wᵢ = W[i]
            t = Aᵢ == Aᵢ
            n += Wᵢ * t
            m += Wᵢ * Aᵢ * t
        end
        return m / n
    end
    # Can't have NaNs if array is all Integers
    function _nanmean(A::Array{<:Integer}, W, ::Colon)
        n = zero(eltype(W))
        m = zero(promote_type(eltype(W), eltype(A)))
        @avx for i ∈ eachindex(A)
            Wᵢ = W[i]
            n += Wᵢ
            m += Wᵢ * A[i]
        end
        return m / n
    end
    # Optimized AVX method for floats
    function _nanmean(A::AbstractArray{<:AbstractFloat}, W, ::Colon)
        T1 = eltype(W)
        T2 = promote_type(eltype(W), eltype(A))
        n = zero(T1)
        m = zero(T2)
        @avx for i ∈ eachindex(A)
            Aᵢ = A[i]
            Wᵢ = W[i]
            t = Aᵢ==Aᵢ
            n += ifelse(t, Wᵢ, zero(T1))
            m += ifelse(t, Wᵢ * Aᵢ, zero(T2))
        end
        return m / n
    end
    export nanmean


    """
    ```julia
    nanstd(A, [W]; dims)
    ```
    Calculate the standard deviation (optionaly weighted), ignoring NaNs, of an
    indexable collection `A`, optionally along a dimension specified by `dims`.
    """
    nanstd(A; dims=:, drop=false) = possiblydropdims(_nanstd(A, dims), drop, dims)
    function _nanstd(A, region)
        mask = nanmask(A)
        N = sum(mask, dims=region)
        s = sum(A.*mask, dims=region)./N
        d = A .- s # Subtract mean, using broadcasting
        @avx for i ∈ eachindex(d)
            dᵢ = d[i]
            d[i] = ifelse(mask[i], dᵢ * dᵢ, 0)
        end
        s .= sum(d, dims=region)
        @avx for i ∈ eachindex(s)
            s[i] = sqrt( s[i] / max((N[i] - 1), 0) )
        end
        return s
    end
    function _nanstd(A, ::Colon)
        n = 0
        m = zero(eltype(A))
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            t = Aᵢ == Aᵢ # False for NaNs
            n += t
            m += Aᵢ * t
        end
        mu = m / n
        s = zero(typeof(mu))
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            d = (Aᵢ - mu) * (Aᵢ == Aᵢ)# zero if Aᵢ is NaN
            s += d * d
        end
        return sqrt(s / max((n-1), 0))
    end
    function _nanstd(A::AbstractArray{<:AbstractFloat}, ::Colon)
        n = 0
        T = eltype(A)
        m = zero(T)
        @avx for i ∈ eachindex(A)
            Aᵢ = A[i]
            t = Aᵢ==Aᵢ
            n += t
            m += ifelse(t, Aᵢ, zero(T))
        end
        mu = m / n
        s = zero(typeof(mu))
        @avx for i ∈ eachindex(A)
            Aᵢ = A[i]
            d = ifelse(Aᵢ==Aᵢ, Aᵢ - mu, 0)
            s += d * d
        end
        return sqrt(s / max((n-1), 0))
    end

    nanstd(A, W; dims=:, drop=false) = possiblydropdims(_nanstd(A, W, dims), drop, dims)
    function _nanstd(A, W, region)
        mask = nanmask(A)
        n = sum(mask, dims=region)
        w = sum(W.*mask, dims=region)
        s = sum(A.*W.*mask, dims=region) ./ w
        d = A .- s # Subtract mean, using broadcasting
        @avx for i ∈ eachindex(d)
            dᵢ = d[i]
            d[i] = (dᵢ * dᵢ * W[i]) * mask[i]
        end
        s .= sum(d, dims=region)
        @avx for i ∈ eachindex(s)
            s[i] = sqrt((s[i] * n[i]) / (w[i] * (n[i] - 1)))
        end
        return s
    end
    function _nanstd(A, W, ::Colon)
        n = 0
        w = zero(eltype(W))
        m = zero(promote_type(eltype(W), eltype(A)))
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            Wᵢ = W[i]
            t = Aᵢ == Aᵢ
            n += t
            w += Wᵢ * t
            m += Wᵢ * Aᵢ * t
        end
        mu = m / w
        s = zero(typeof(mu))
        @inbounds @simd for i ∈ eachindex(A)
            Aᵢ = A[i]
            d = Aᵢ - mu
            s += (d * d * W[i]) * (Aᵢ == Aᵢ) # Zero if Aᵢ is NaN
        end
        return sqrt(s / w * n / (n-1))
    end
    function _nanstd(A::AbstractArray{<:AbstractFloat}, W, ::Colon)
        n = 0
        Tw = eltype(W)
        Tm = promote_type(eltype(W), eltype(A))
        w = zero(Tw)
        m = zero(Tm)
        @avx for i ∈ eachindex(A)
            Aᵢ = A[i]
            Wᵢ = W[i]
            t = Aᵢ==Aᵢ
            n += t
            w += ifelse(t, Wᵢ,  zero(Tw))
            m += ifelse(t, Wᵢ * Aᵢ, zero(Tm))
        end
        mu = m / w
        Tmu = typeof(mu)
        s = zero(Tmu)
        @avx for i ∈ eachindex(A)
            Aᵢ = A[i]
            d = Aᵢ - mu
            s += ifelse(Aᵢ==Aᵢ, d * d * W[i], zero(Tmu))
        end
        return sqrt(s / w * n / (n-1))
    end
    export nanstd


    """
    ```julia
    nanmedian(A; dims)
    ```
    Calculate the median, ignoring NaNs, of an indexable collection `A`,
    optionally along a dimension specified by `dims`.
    """
    nanmedian(A; dims=:, drop=false) = possiblydropdims(_nanmedian(A, dims), drop, dims)
    function _nanmedian(A, ::Colon)
        t = nanmask(A)
        return any(t) ? median(A[t]) : float(eltype(A))(NaN)
    end
    function _nanmedian(A, region)
        s = size(A)
        if region == 2
            t = Array{Bool}(undef, s[2])
            result = Array{float(eltype(A))}(undef, s[1], 1)
            for i=1:s[1]
                nanmask!(t, A[i,:])
                result[i] = any(t) ? median(A[i,t]) : float(eltype(A))(NaN)
            end
        elseif region == 1
            t = Array{Bool}(undef, s[1])
            result = Array{float(eltype(A))}(undef, 1, s[2])
            for i=1:s[2]
                nanmask!(t, A[:,i])
                result[i] = any(t) ? median(A[t,i]) : float(eltype(A))(NaN)
            end
        else
            result = _nanmedian(A, :)
        end
        return result
    end
    export nanmedian


    """
    ```julia
    nanmad(A; dims)
    ```
    Median absolute deviation from the median, ignoring NaNs, of an indexable
    collection `A`, optionally along a dimension specified by `dims`.
    Note that for a Normal distribution, sigma = 1.4826 * MAD
    """
    function nanmad(A; dims=:)
        s = size(A)
        if dims == 2
            t = Array{Bool}(undef, s[2])
            result = Array{float(eltype(A))}(undef, s[1], 1)
            for i=1:s[1]
                nanmask!(t, A[i,:])
                result[i] = any(t) ? median(abs.( A[i,t] .- median(A[i,t]) )) : float(eltype(A))(NaN)
            end
        elseif dims == 1
            t = Array{Bool}(undef, s[1])
            result = Array{float(eltype(A))}(undef, 1, s[2])
            for i=1:s[2]
                nanmask!(t, A[:,i])
                result[i] = any(t) ? median(abs.( A[t,i] .- median(A[t,i]) )) : float(eltype(A))(NaN)
            end
        else
            t = nanmask(A)
            result = any(t) ? median(abs.( A[t] .- median(A[t]) )) : float(eltype(A))(NaN)
        end
        return result
    end
    export nanmad


    """
    ```julia
    nanaad(A; dims)
    ```
    Mean (average) absolute deviation from the mean, ignoring NaNs, of an
    indexable collection `A`, optionally along a dimension specified by `dims`.
    Note that for a Normal distribution, sigma = 1.253 * AAD
    """
    nanaad(A; dims=:, drop=false) = possiblydropdims(_nanmean(abs.(A .- _nanmean(A, dims)), dims), drop, dims)
    export nanaad


## -- moving average

    """
    ```julia
    movmean(x::AbstractVecOrMat, n::Number)
    ```
    Simple moving average of `x` in 1 or 2 dimensions, spanning `n` bins (or n*n in 2D), returning an array of the same size as `x`.
    For the resulting moving average to be symmetric, `n` must be an odd integer; if `n` is not an odd integer, the first odd integer greater than `n` will be used instead.
    """
    function movmean(x::AbstractVector, n::Number)
        mean_type = Base.promote_op(/, eltype(x), Int64)
        m = Array{mean_type}(undef, size(x))
        t = Array{Bool}(undef, length(x))
        halfspan = ceil((n-1)/2)
        ind = 1:length(x)
        @inbounds for i in ind
            l = ceil(i-halfspan)
            u = ceil(i+halfspan)
            @avx @. t = l <= ind <= u
            m[i] = nanmean(view(x, t))
        end
        return m
    end
    function movmean(x::AbstractMatrix, n::Number)
        mean_type = Base.promote_op(/, eltype(x), Int64)
        m = Array{mean_type}(undef, size(x))
        t = Array{Bool}(undef, size(x))
        halfspan = ceil((n-1)/2)
        iind = repeat(1:size(x,1), 1, size(x,2))
        jind = repeat((1:size(x,2))', size(x,1), 1)
        @inbounds for k = 1:length(x)
            i = iind[k]
            j = jind[k]
            il = (i-halfspan)
            iu = (i+halfspan)
            jl = (j-halfspan)
            ju = (j+halfspan)
            @avx @. t = (il <= iind <= iu) & (jl <= jind <= ju)
            m[i,j] = nanmean(view(x, t))
        end
        return m
    end
    export movmean


## --- End of File
