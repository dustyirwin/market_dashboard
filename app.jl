module MarketsController

# set up Genie development environmet
using GenieFramework
using GenieFramework.StippleUI

@genietools

# libs
using Dates, CSV, HTTP, DataFrames, Statistics

include("Markets.jl")
using .Markets

# custom href macro
macro href(expr)
  s = @eval __module__ string($(expr))
  Expr(:kw, Symbol(":href.attr"), s)
end

# data dict
s = Dict(
  :queries => Dict(),
  :csvs => Dict(),
  :query_name => "",
)

# add reactive code to make the UI interactive
@app begin

  # triggers reactivity
    @in isbusy = false
    @in iserror = false
    @in save_query = false
    @in run_query = false
    @in delete_query = false
    @in clear_results = false
    @in saved_queries = []
    @in selected_query = []
    @in append_results = false

  # queries
    @in query_name = ""
    @in query_market = ""
    @in query_pages = 1
    @in query_max_pages = 1
    @in query_category = ""
    @in query_keywords = ""
    @in query_filter = []
    @in query_location = ""
    
  # ui elems
    @out user_message = "Setting up..."
    @out query_url = "www.google.com"
    @out available_markets = [ v["name"] for (k,v) in markets ]
    @out market_categories = []
    @out market_filters = []
    @out market_locations = []

  # output data
    @out query_tabs = "query_items"
    @out results = []
    @out results_df = DataFrame()
    @out results_dt_pagination = StippleUI.DataTablePagination(rows_per_page=15)
    @out results_dt = StippleUI.DataTable()
    
    @out num_results = 0
    @out num_items = 0
    @out sales_price_mean = 0.0
    @out sales_price_median = 0.0
    @out sales_price_std = 0.0
    @out sales_price_min = 0.0
    @out sales_price_max = 0.0

    @out card_contents = []
    
    @out card_detail_contents = []
    @in get_item_descriptions = false
    @in card_detail_idxs = []
    @in detail_tabs = ""

  # results data
    iobuff = IOBuffer()

  @onchange isready begin
    isbusy = true
    
    @info "markets detected: $(keys(markets))"

    isbusy = false
    @info "App is ready! s.data keys: $(keys(s))"
  end

  @onchange isbusy begin
    @info "App is busy!"
  end

  @onchange selected_query begin
    @info "selected_query: $selected_query"
    
    if !isempty(selected_query)
      query = s[:queries][ selected_query[end] ]

      @info "query: $query"

      query_name = query.name
      query_url = query.query_url
      query_market = query.market
      query_keywords = query.keywords
      query_category = query.category
      query_filter = query.filters
      query_max_pages = query.max_pages
      query_url = query.query_url
      query_pages = query.pages
    
    else
      query_name = ""
      query_market = ""
      query_keywords = ""
      query_category = ""
      query_filter = []
      query_max_pages = 0
      query_pages = 0
      query_url = ""
    end
  end 

  @onchange run_query begin
    @info "run_query button pressed!"
    isbusy = true

    if !isempty(selected_query) && query_market != "" && !(nothing in selected_query)
      
      ipg = if query_market == "newegg"
        96
      elseif query_market == "ebay"
        200  # ~240 is actual limit, but ebay only return 209 images from a single query, 200 is sufficient
      else
        1
      end

      for sel_query_name in selected_query
      
        user_message = "Processing query: $sel_query_name"
        query = s[:queries][ sel_query_name ]
        @info "query: $query"

        if !isempty(selected_query)
          query_name = query.name
          query_url = query.query_url
          query_market = query.market
          query_keywords = query.keywords
          query_category = query.category
          query_filter = query.filters
          query_max_pages = query.max_pages
          query_pages = query.pages
          end

        filters = if isempty(query_filter) || nothing in query_filter
            ""
          else
          [ markets[query_market]["filters"](query_market)[filter] for filter in query_filter] |> join
          end

        category = if query_category == ""
          "All"
          else
            markets[query_market]["categories"][query_category]
          end

          query_url = markets[query_market]["query_url"](query_keywords, category, filters, query_pages, ipg)
          _results_df, results, num_results = scan(markets[query_market], query_keywords, category, filters, query_pages, get_item_descriptions)
          
          if append_results
            results_df = vcat(results_df, _results_df, cols=:union)
            _results_df = nothing
          else
            results_df = _results_df
            _results_df = nothing
          end

          query_max_pages = ceil(Int, num_results / ipg)
          results_item_names = results_df.name[1:10] |> collect
          results_item_prices = results_df.sales_price[1:10] |> collect
          results_item_imgs = results_df.imgs[1:10] |> collect
          
          results_dt = StippleUI.DataTable(results_df)
          # clear out buffer
          truncate(iobuff, 0)
          
          # write data to buffer
          CSV.write(iobuff, results_df)

        s[:query_name] = join(selected_query, "_")
      end

      if num_results > 0
        item_names = results_df.name[1:(num_results > ipg ? ipg : num_results)] |> collect
        item_urls = results_df.item_url[1:(num_results > ipg ? ipg : num_results)] |> collect
        item_img_urls = results_df.imgs[1:(num_results > ipg ? ipg : num_results)] |> collect
        sales_prices = results_df.sales_price[1:(num_results > ipg ? ipg : num_results)] |> collect
        item_ids = results_df.id[1:(num_results > ipg ? ipg : num_results)] |> collect
        item_descs = results_df.description[1:(num_results > ipg ? ipg : num_results)] |> collect
        market_names = results_df.market[1:(num_results > ipg ? ipg : num_results)] |> collect
        card_contents = zip(1:ipg, item_names, item_urls, item_img_urls, sales_prices, item_ids, item_descs, market_names) |> collect
        
          # calculating sales_price metrics
        num_items = nrow(results_df)
        parsed_prices = [ typeof(p) <: AbstractString ? parse(Float64, replace(p, "\$"=>"",","=>"")) : p for p in results_df.sales_price ]
        
        sales_price_mean = mean(parsed_prices) |> x -> round(x, digits=2)
        sales_price_median = median(parsed_prices) |> x -> round(x, digits=2)
        sales_price_std = std(parsed_prices) |> x -> round(x, digits=2)
        sales_price_min = minimum(parsed_prices) |> x -> round(x, digits=2)
        sales_price_max = maximum(parsed_prices) |> x -> round(x, digits=2)
        
        # card_content array length = 8
        
        card_detail_idxs = []
      end
    end

    isbusy = false
  end

  @onchange save_query begin
    @info "save_query button pressed!"
    iserror = false

    if !isempty(query_keywords) && !isempty(query_market)
      query = Query(
        name = query_name,
        market = query_market,
        keywords = query_keywords,
        category = query_category,
        filters = query_filter,
        max_pages = query_max_pages,
        pages = query_pages,
        query_url = query_url,
      )
      
      s[:queries][query.name] = query

      saved_queries = keys(s[:queries]) |> collect

      @info "saved query: $query"
    else
      user_message = "Please enter a query and select a market!"
      iserror = true
    end
  end

  @onchange clear_results begin
    @info "clear_results button pressed!"
    results_df = DataFrame()
    results_dt = StippleUI.DataTable(results_df)
    card_contents = []
    card_detail_contents = []
    card_detail_idxs = []
  end

  @onchange delete_query begin
    @info "delete_query button pressed!"

    for sel_query_name in selected_query
      delete!(s[:queries], sel_query_name)
    end

    saved_queries = keys(s[:queries]) |> collect
  end

  @onchange query_market, query_category, query_filter, query_keywords, query_max_pages begin

    if query_market != ""
      
      @info "market_categories: $market_categories"
      query_name = join([query_market, query_keywords, query_category, join(query_filter, '&')], "_")
      market_categories = markets[ query_market ]["categories"] |> keys |> collect
      market_locations = markets[ query_market ]["locations"] |> keys |> collect
      market_filters = markets[ query_market ]["filters"](query_category) |> keys |> collect      
    end
  end

  @onchange card_detail_idxs begin

    _card_detail_idxs = []

    for idx in card_detail_idxs  
      if idx ∉ _card_detail_idxs
        push!(_card_detail_idxs, idx)
      end
    end

    card_detail_contents = []

    for idx in _card_detail_idxs
      card_detail_content = []

      push!(card_detail_content, card_contents[idx]...)
      card_detail_content[7] = markets[query_market]["get_item_desc"](card_contents[idx][6])
      push!(card_detail_content, markets[query_market]["item_img_srcs"](card_contents[idx][3], query_filter))

      @info "card_detail_content: $card_detail_content"
      push!(card_detail_contents, card_detail_content)
    end

    card_detail_contents = card_detail_contents |> collect

    #@info "card_detail_idxs: $card_detail_idxs"
    #@info "card_detail_contents: $card_detail_contents"
  end

  route("/query/download_csv", method=GET) do
    qn = s[:query_name]
    headers = Dict(
      "Content-Type" => "text/csv",
      "Content-Disposition" => "attachment; filename=\"$(qn)_$(Date(now())).csv\""
    )
    HTTP.Response(200, headers, String(take!(iobuff)))
  end
end

@page("/", "$(@__DIR__)/views/markets_ui.jl")

end