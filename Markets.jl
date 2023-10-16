module Markets

import Base: @kwdef

using Dates, HTTP, DataFrames, Gumbo, Cascadia, DataStructures, Base.Threads

export Item, Query, Search, scan, market_items_to_df, headers, proxies, markets, card_content

headers = Dict(
  1 => Dict("User-agent" => "Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.120 Safari/537.36"),
  2 => Dict("User-agent" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/33.0.1750.149 Safari/537.36"),
  3 => Dict("User-agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.102 Safari/537.36"),)

proxies = Dict(
  1 => "https://162.210.211.225:57364",
  2 => "https://45.79.64.225:3128",)  # from https://free-proxy-list.net/

# used to capture item ids for description retrieval
item_id = 1

markets = let
  d = OrderedDict()

  d["ebay"] = Dict(
    "name" => "ebay",
    "keywords" => (keywords) -> replace(keywords, " " => "+"),
    "categories" => OrderedDict(
      "All" => "",
      "Video Games" => "139973",
      "Video Game Consoles" => "1249",
      "Cell Phones & Accessories" => "15032",
      "Consumer Electronics" => "293",
      "Computer Components & Parts" => "175673",
      "Computers/Tablets & Networking" => "58058",
      "Toys & Hobbies" => "220",
      "Collectibles" => "1",
      ),
    "locations" => OrderedDict(
      "Salt Lake City, UT" => "84004",
      "Portland, OR" => "97035",
      "Seattle, WA" => "98101",
      ),
    "filters" => (query_category) -> OrderedDict(
      "US Only" => "&LH_PrefLoc=1",
      "Buy-It-Now" => "&LH_BIN=1",
      "*North America" => "&LH_PrefLoc=3",
      "*NTSC-(US/Canada)" => query_category == "Video Games" ? "&rt=nc&Region%2520Code=NTSC%252DU%252FC%2520%2528US%252FCanada%2529&_dcat=139973" : "",
      "Used - Very Good" => "&LH_ItemCondition=4000",
      "Used - Good" => "&LH_ItemCondition=5000",
      "Free Shipping" => "&LH_FS=1",
      "Sort: Time: Newly Listed" => "&_sop=10",
      "Sort: Time: Ending Soonest" => "&_sop=1",
      "*Auction" => "&LH_Auction=1",
      "*Search in Description" => "&LH_TitleDesc=1",
      "*Listed as Lots" => "&LH_ItemCondition=7000",
      "*Free Returns" => "&LH_Returns=1",
      "*Authorized Seller" => "&LH_Auction=1&LH_ItemCondition=3000",
      ),
    "query_url" => (query, category="", filters="", page=1, ipg=200) ->
      """https://www.ebay.com/sch/i.html?_from=R40&_nkw=$query$filters&_dmd=2&_sacat=$category&_pgn=$page&_ipg=$ipg""",
    "num_items" => (response) -> try 
      html = parsehtml(String(response.body)).root
      s = eachmatch(sel".srp-controls__count-heading", html)[1][1][1].text
      parse(Int64, replace(s, "," => ""))
      catch e
        @warn "error getting num_items: $e"
        0
      end,
    "item_datas" => (response) -> let
      html = parsehtml(String(response.body)).root
      ul = eachmatch(sel"ul.srp-results", html)[1]
      eachmatch(sel"li.s-item", ul)
      end,
    "items" => (item_datas, query_url, category, filters) -> Item[ Item(
      market="ebay",  # market
      id=try
        global item_id = match(r"/\d+/?", eachmatch(sel"a.s-item__link", item_html)[1].attributes["href"]).match[2:end]
        item_id
      catch
        missing
      end,  # id
      name=try
          eachmatch(sel"div.s-item__title", item_html)[1][1][1].text
        catch e
          @warn "error getting name for item number $i: $e from item_html: item_html"
          missing
        end, # name
      category=category,
      filters=filters,
      sales_price=try
        eachmatch(sel"span.s-item__price", item_html)[1][1][1].text
        catch
          try
            eachmatch(sel"span.s-item__price", item_html)[1][1].text
          catch e
            @warn "error getting sales_price for item number $i: $e from item_html: item_html"
            missing
          end
        end,  # sales_price
      shipping=try
          eachmatch(sel"span.s-item__shipping", item_html)[1][1].text
        catch e
          @warn "error getting shipping for item number $i: $e from item_html: item_html"
          missing
        end,  # shipping
      imgs=try
        [img.attributes["src"] for img in eachmatch(sel"img", item_html)]
        catch e
          @warn "error getting imgs for item number $i: $e from item_html: item_html"
          missing
        end,  # imgs
      description=missing,
      query_url=query_url,
      item_url=try
          eachmatch(sel"a", item_html)[1].attributes["href"]
        catch e
          @warn "error getting url for item number $i: $e from item_html: $item_html"
          missing
        end,  # url
        ) for (i, item_html) in enumerate(item_datas)
      ],
    "item_img_srcs" => (item_url, filters) -> let
      @info "getting item_img_srcs for $item_url with filters: $filters"
      r = HTTP.get(item_url)

      detail_html = if occursin("Sold", join(filters))
        try
          html = parsehtml(String(r.body)).root
          orig_url = eachmatch(sel"span.vi-original-listing", html)[1][1].attributes["href"]
          _r = HTTP.get(orig_url)
          parsehtml(String(_r.body)).root
        catch e
          @warn "error getting detail_html for sold item, trying original url: $e"
          parsehtml(String(r.body)).root
        end
      else
        parsehtml(String(r.body)).root
      end

      carousel_items = try
        eachmatch(sel"div.ux-image-carousel-item", detail_html)
      catch e
        @info "No image carousel found, trying picture panel elem"
        try
          eachmatch(sel"div.pic_panel", detail_html)
        catch
          @warn "No image carousel or picture panel found!"
          []
        end
      end

      imgs = [eachmatch(sel"img", item)[1] for item in carousel_items]

      img_srcs = []

      for img in imgs

        if haskey(img.attributes, "data-zoom-src")
          src = img.attributes["data-zoom-src"]
        elseif haskey(img.attributes, "data-src")
          src = img.attributes["data-src"]
        elseif haskey(img.attributes, "src")
          src = img.attributes["src"]
        end

        push!(img_srcs, src)
      end

      img_srcs
      end,
    "get_item_desc" => (item_id) -> try
        desc_url = "https://vi.vipr.ebaydesc.com/ws/eBayISAPI.dll?item=$item_id"
        html = HTTP.get(desc_url) |> String |> parsehtml |> x -> x.root
        [ el[1].text for el in [eachmatch(sel"p", html)..., eachmatch(sel"b", html)...] ]
      catch e 
        @warn "error getting description for item $item_id: $e"
        missing
      end,
  )
end

@kwdef mutable struct Item
  id::Union{String,Missing} = missing
  name::Union{String,Missing} = missing
  market::Union{String,Missing} = missing
  location::Union{String,Missing} = missing
  category::Union{String,Missing} = missing
  filters::Union{String,Missing} = missing
  sales_price::Union{String,Missing} = missing
  shipping::Union{String,Missing} = missing
  imgs::Vector{Union{String,Missing}} = [ missing ]
  description::Union{Vector{String},Missing} = [ missing ]
  item_url::Union{String,Missing} = missing
  query_url::Union{String,Missing} = missing
end

@kwdef mutable struct Query
  name::String
  market::Union{String, Missing}=""
  keywords::Union{String, Missing}=""
  category::Union{String, Missing}=""
  filters::Union{Vector{String}, Missing}=""
  pages::Union{Integer, Missing}=1
  max_pages::Union{Integer, Missing}=1
  query_url::Union{String, Missing}=""  
end

function create_query(name::String, keywords::String, category::Union{Int64,String}, filters::Union{String,Array{String,1}}, max_pages::Int64)
  query_url = markets[name]["query_url"](replace(keywords, " " => "+"), category, filters)
  return Query(name, keywords, category, join(filters), max_pages, query_url)
end

function market_items_to_df(items::Vector{Item}, get_item_desc=false, sortby=:price)
  DataFrame(
    market=[item.market for item in vcat(items...)],
    name=[typeof(item.name) != String ? missing : replace(item.name, "," => "") for item in vcat(items...)],
    sales_price=[typeof(item.sales_price) != String ? missing : item.sales_price for item in vcat(items...)],
    shipping_cost=[typeof(item.shipping) != String ? missing : item.shipping for item in vcat(items...)],
    category=[typeof(item.category) != String ? missing : item.category for item in vcat(items...)],
    description=[typeof(item.description) != String ? missing : item.description for item in vcat(items...)],
    id=[typeof(item.id) != String ? missing : item.id for item in vcat(items...)],
    filters=[typeof(item.filters) != String ? missing : item.filters for item in vcat(items...)],
    imgs=[typeof(item.imgs) != Vector{Union{String,Missing}} ? [ missing ] : item.imgs for item in vcat(items...)],
    item_url=[typeof(item.item_url) != String ? missing : item.item_url for item in vcat(items...)],
    query_url=[typeof(item.query_url) != String ? missing : item.query_url for item in vcat(items...)],
    get_details=[ false for item in vcat(items...)],
  )
end

function scan(market::Dict, keywords::String, category="", filters="", query_pages=1, get_item_descriptions=false, headers = headers)
  
  @info "scanning $(uppercase(market["name"])) for $keywords \n category: $category \n  filters: $filters \n  pages: $query_pages \n  get_item_descriptions: $(join(get_item_descriptions))"
  
  headers = headers[rand(1:length(headers))]
  items = Item[]
  num_items = ""

  for page in 1:query_pages
    keywords = market["keywords"](keywords)
    query_url = market["query_url"](keywords, category, filters, page)
    println("$(uppercase(market["name"])) query url: $query_url")

    # throttle
    page != 1 && sleep(rand(1:0.1:2))
    response = HTTP.get(query_url, headers)

    if page == 1
      num_items = market["num_items"](deepcopy(response))
    end

    item_datas = market["item_datas"](response)

    append!(items, market["items"](item_datas, query_url, category, filters))

    if get_item_descriptions
      @info "getting item descriptions, this can take awhile..."

      @time @threads for item in items
        item.description = market["get_item_desc"](item.id)
      end
    end

    items
  end # for

  num_items = if num_items isa String
    parse(Int, num_results_str)
  elseif num_items isa Integer
    num_items
  else
    0
  end

  items_df = market_items_to_df(items)

  return items_df, items, num_items
end

end
