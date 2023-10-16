[
  banner("{{user_message}}", class="bg-primary text-white", [
    template("", "v-slot:action", [
      btn("Dismiss", flat=true, color="white"),
    ])
    ], @iif(:isbusy)),

    # error message
  banner("{{user_message}}", class="bg-primary text-white", [
      template("", "v-slot:action", [
        btn("Dismiss", flat=true, color="white"),
      ])
    ], @iif(:iserror)),

   cell(style="margin: 15px", [
    
    row(style="padding:0px; margin: 0px;", [
     
      cell(class="st-col col-4 col-sm", style="padding:0px; margin: 0px; margin-right: 20px", [
        Stipple.select(:selected_query, options=:saved_queries, multiple=true, label="Select existing queries", dense=true, clearable=true),
        br(),
        #row([ p("Query URL: "), a("{{query_url}}") ]),
        row(class="justify-evenly", [
          p("total items found for query: "), b(" {{num_results}}"),
          p("items retreived: "), b(" {{num_items}}"),
          ]),
        row(class="justify-evenly", [
          p("retreived sales price stats: "),
          p("mean: "), b("$('$'){{sales_price_mean}}"), 
          p("median: "), b("$('$'){{sales_price_median}}"), 
          p("std: "), b("$('$'){{sales_price_std}}"), 
          p("min: "), b("$('$'){{sales_price_min}}"), 
          p("max: "), b("$('$'){{sales_price_max}}")
        ]),
        row(style="align-items: center;",[
          btngroup(class="justify-left", push=true, [
            btn(@click("save_query = !save_query"), color="primary", label="Save Querie(s)", rounded=true, outline=false, dense=true, push=true, style="padding: 5px"),
            btn(@click("delete_query = !delete_query"), color="primary", label="Delete Querie(s)", rounded=true, outline=false, dense=true, push=true, style="padding: 5px"),
            btn(@click("clear_results = !clear_results"), label="Clear Results", color="primary", rounded=true, outline=false, dense=true, push=true, style="padding: 5px"),
            btn(href="/query/download_csv", color="primary", "Download DataTable", rounded=true, outline=false,dense=true, push=true, style="padding: 5px"),
          ]),
        ]),
        row(class="q-pa-sm", style="align-items:center; margin-top:15px; margin-right: 60px;", [
          b("Max pages ({{ query_max_pages }}): ", style="margin-right: 5px;"),
          slider(1:Symbol("query_max_pages"), @bind(:query_pages), snap=true, labelalways=true, dense=true, style="max-width: 25%; margin: 10px; padding: 10px;"),
          cell([
            checkbox(@bind(:append_results), label="Append results to existing datatable", dense=true, style="padding: 5px;"),
            tooltip("Append results from multiple queries into one dataframe", delay="1000")
          ]),
          spinner(style="align-items: center;", color="primary", size="2em", @iif(:isbusy)),
          btn(@click("run_query = !run_query"), label="Run Querie(s)", color="green", rounded=true, dense=false, push=true, @els(:isbusy)),
        ]),
      ]),
      cell(class="st-col col-4 col-sm", style="buffer:0px; padding:0px; margin: 0px;", [
        textfield(@bind(:query_name), label="Query name", dense=true),
        Stipple.select(:query_market, options=:available_markets, label="Select data source", clearable=true, dense=true, rounded=true, outline=true,),
        textfield(@bind(:query_keywords), label="Enter query keywords here", clearable=true, dense=true),
        Stipple.select(:query_category, options=:market_categories, label="Select categories, no entry will search all categories", clearable=true, dense=true),
        Stipple.select(:query_filter, options=:market_filters, label="Select query filters here", clearable=true, multiple=true, dense=true),
        Stipple.select(:query_location, options=:market_locations, label="Select query location", clearable=true, multiple=false, dense=true),
        ]),
    ]),
  ]),
  cell(class="col-sm", style="text-align: center; buffer:0px; padding:0px; margin: 0px;", [
    tabgroup(:query_tabs, inlinelabel=true, class="text-dark-grey shadow-2", [
      tab(name="query_items", icon="style", label="Items"),
      tab(name="item_details", icon="info", label="Details"),
      tab(name="query_datatable", icon="grid_on", label="DataTable"),
    ]),
    
    tabpanels(:query_tabs, [
      
      tabpanel(name="query_items", [
        
        scrollarea(style="height: 875px; width: auto;", [
          
          row(class="justify-evenly", style="margin: 5px;", [
            
            card(@recur("[idx,name,item_url,img_url,price,id,descriptions,market] in card_contents"), 
              spinner__color="white", style="max-height: auto; width: 200px;", [
              
              a(@href(:item_url), target="_", [
                imageview(src=:img_url),
                b("{{name}}", style="margin: 5px;"),
              ]),
              br(),
              b("({{market}}) sales price: {{price}}", style="margin: 5px;"),
              p("{{description}}", style="margin: 5px;", @recur("description in descriptions")),
              btn(@click("card_detail_idxs.push(idx)"), label="Get details", color="primary", 
                dense=true, style="margin: 5px;", outline=true),
            ]),
          ]),
        ]),
      ]),

      tabpanel(name="item_details", [

        tabgroup(:detail_tabs, inlinelabel=false, class="text-dark-grey shadow-2", [
          tab(name=:name, label=:name, @recur("[idx,name,item_url,img_url,price,id,descriptions,market,img_srcs] in card_detail_contents"))
        ]),

        tabpanels(:detail_tabs, [
          
          tabpanel(name=:name, clearable=true,   @recur("[idx,name,item_url,img_url,price,id,descriptions,market,img_srcs] in card_detail_contents"), [

            scrollarea(style="height: 800px; width: auto;", [

              cell(class="justify-evenly", style="bottom-margin: 15px;", [
                
                row(spinner__color="white", [
                  
                  cell([

                    a(@href(:item_url), target="_", [
                      h3("{{name}}", style="margin: 5px;"),
                    ]),
                    h4("({{market}}) sales price: {{price}}", style="margin: 5px;"),
                    p("{{description}}", style="margin: 5px;", @recur("description in descriptions")),
                    row([
                      imageview(src=:img_src, style="max-width: 375; max-height: auto; margin: 5px", @recur("img_src in img_srcs"))
                    ]),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]),

      tabpanel(name="query_datatable", [
        table(:results_dt, pagination=:results_dt_pagination, spinner__color="white", dense=true),
      ]),
    ]),
  ]),
] |> string