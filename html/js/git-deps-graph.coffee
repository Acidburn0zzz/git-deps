jQuery = require "jquery"
$ = jQuery
d3 = require "d3"
d3tip = require "d3-tip"
d3tip d3

global.gdn = require "./git-deps-noty.coffee"
global.gdd = require "./git-deps-data.coffee"
global.gdl = require "./git-deps-layout.coffee"

fullScreen = require "./fullscreen"

SVG_MARGIN = 2    # space around <svg>, matching #svg-container border
RECT_MARGIN = 14  # space in between <rects>
PADDING = 5       # space in between <text> label and <rect> border
EDGE_ROUTING_MARGIN = 3

svg_width = 960
svg_height = 800
old_svg_height = undefined
old_svg_width = undefined

color = d3.scale.category20()

global.d3cola = cola.d3adaptor()
d3cola \
    .flowLayout("y", 150) \
    .avoidOverlaps(true)
    #.linkDistance(60)
    #.symmetricDiffLinkLengths(30)
    #.jaccardLinkLengths(100)

# d3 visualization elements
container = undefined
svg = undefined
fg = undefined
node = undefined
path = undefined
tip = undefined
tip_template = undefined
zoom = undefined

options = undefined # Options will be retrieved from web server

jQuery ->
    d3.json "options", (error, data) ->
        options = data

    d3.html "tip-template.html", (error, html) ->
        tip_template = html

    #setup_default_form_values();
    $("form.commitish").submit (event) ->
        event.preventDefault()
        add_commitish $(".commitish input").val()

setup_default_form_values = ->
    $("input[type=text]").each(->
        $(this).val $(this).attr("defaultValue")
        $(this).css color: "grey"
    ).focus(->
        if $(this).val() is $(this).attr("defaultValue")
            $(this).val ""
            $(this).css color: "black"
    ).blur ->
        if $(this).val() is ""
            $(this).val $(this).attr("defaultValue")
            $(this).css color: "grey"

resize_window = ->
    calculate_svg_size_from_container()
    fit_svg_to_container()
    redraw true

redraw = (transition) ->
    # if mouse down then we are dragging not panning
    # if nodeMouseDown
    #     return
    ((if transition then fg.transition() else fg)) \
        .attr "transform",
              "translate(#{zoom.translate()}) scale(#{zoom.scale()})"

graph_bounds = ->
    x = Number.POSITIVE_INFINITY
    X = Number.NEGATIVE_INFINITY
    y = Number.POSITIVE_INFINITY
    Y = Number.NEGATIVE_INFINITY
    fg.selectAll(".node").each (d) ->
        x = Math.min(x, d.x - d.width / 2)
        y = Math.min(y, d.y - d.height / 2)
        X = Math.max(X, d.x + d.width / 2)
        Y = Math.max(Y, d.y + d.height / 2)
    return {} =
        x: x
        X: X
        y: y
        Y: Y

fit_svg_to_container = ->
    svg.attr("width", svg_width).attr("height", svg_height)

full_screen_cancel = ->
    svg_width = old_svg_width
    svg_height = old_svg_height
    fit_svg_to_container()
    #zoom_to_fit();
    resize_window()

full_screen_click = ->
    fullScreen container[0][0], full_screen_cancel
    fit_svg_to_container()
    resize_window()
    #zoom_to_fit();

zoom_to_fit = ->
    b = graph_bounds()
    w = b.X - b.x
    h = b.Y - b.y
    cw = svg.attr("width")
    ch = svg.attr("height")
    s = Math.min(cw / w, ch / h)
    tx = -b.x * s + (cw / s - w) * s / 2
    ty = -b.y * s + (ch / s - h) * s / 2
    zoom.translate([tx, ty]).scale s
    redraw true

window.full_screen_click = full_screen_click
window.zoom_to_fit = zoom_to_fit

add_commitish = (commitish) ->
    init_svg()  unless svg
    draw_graph commitish

calculate_svg_size_from_container = ->
    old_svg_width = svg_width
    old_svg_height = svg_height
    svg_width = container[0][0].offsetWidth - SVG_MARGIN
    svg_height = container[0][0].offsetHeight - SVG_MARGIN

init_svg = ->
    container = d3.select("#svg-container")
    calculate_svg_size_from_container()
    svg = container.append("svg") \
        .attr("width", svg_width) \
        .attr("height", svg_height)
    d3cola.size [svg_width, svg_height]

    d3.select(window).on "resize", resize_window

    zoom = d3.behavior.zoom()

    svg.append("rect") \
        .attr("class", "background") \
        .attr("width", "100%") \
        .attr("height", "100%") \
        .call(zoom.on("zoom", redraw)) \
        .on("dblclick.zoom", zoom_to_fit)

    fg = svg.append("g")
    define_arrow_markers fg

update_cola = ->
    gdl.build_constraints()
    d3cola \
        .nodes(gdd.nodes) \
        .links(gdd.links) \
        .constraints(gdl.constraints)

draw_graph = (commitish) ->
    d3.json "deps.json/" + commitish, (error, data) ->
        if error
            details = JSON.parse(error.responseText)
            gdn.error details.message
            return

        new_data = gdd.add(data)

        unless new_data
            gdn.warn "No new commits or dependencies found!"
            update_rect_explored()
            return
        new_data_notification new_data

        update_cola()

        path = fg.selectAll(".link") \
            .data(gdd.links, link_key)
        path.enter().append("svg:path") \
            .attr("class", "link")
        node = fg.selectAll(".node") \
            .data(gdd.nodes, (d) -> d.sha1) \
            .call(d3cola.drag)
        global.node = node

        node.enter().append("g") \
            .attr("class", "node")
            # Failed attempt to use dagre layout as starting positions
            # https://github.com/tgdwyer/WebCola/issues/63
            # .each(function (d, i) {
            #     var n = gdl.node(d.sha1);
            #     d.x = n.x;
            #     d.y = n.y;
            # });

        draw_nodes fg, node

# Required for object constancy: http://bost.ocks.org/mike/constancy/ ...
link_key = (link) ->
    source = sha1_of_link_pointer(link.source)
    target = sha1_of_link_pointer(link.target)
    return source + " " + target

# ... but even though link sources and targets are initially fed in
# as indices into the nodes array, webcola then replaces the indices
# with references to the node objects.  So we have to deal with both
# cases when ensuring we are uniquely identifying each link.
sha1_of_link_pointer = (pointer) ->
    return pointer.sha1 if typeof (pointer) is "object"
    return gdd.nodes[pointer].sha1

new_data_notification = (new_data) ->
    new_nodes = new_data[0]
    new_deps = new_data[1]
    root = new_data[2]
    notification =
        if root.commitish == root.sha1
            "Analysed dependencies of #{root.abbrev}"
        else
            "<span class=\"commit-ref\">#{root.commitish}</span>
                resolved as #{root.sha1}"
    notification += "<p>#{new_nodes} new commit"
    notification += "s" unless new_nodes == 1
    notification += "; #{new_deps} new " +
        (if new_deps == 1 then "dependency" else "dependencies")
    notification += "</p>"

    gdn.success notification

define_arrow_markers = (fg) ->
    # define arrow markers for graph links
    fg.append("svg:defs").append("svg:marker") \
        .attr("id", "end-arrow") \
        .attr("viewBox", "0 -5 10 10") \
        .attr("refX", 6) \
        .attr("markerWidth", 8) \
        .attr("markerHeight", 8) \
        .attr("orient", "auto") \
      .append("svg:path") \
        .attr("d", "M0,-5L10,0L0,5") \
        .attr "fill", "#000"

draw_nodes = (fg, node) ->
    # Initialize tooltip
    tip = d3.tip().attr("class", "d3-tip").html(tip_html)
    fg.call tip
    hide_tip_on_drag = d3cola.drag().on("dragstart", tip.hide)
    node.call hide_tip_on_drag

    rect = node.append("rect") \
        .attr("rx", 5) \
        .attr("ry", 5)

    update_rect_explored()

    rect.on "dblclick", (d) ->
        if d.explored
            gdn.warn "Commit #{d.name} already explored"
        else
            add_commitish d.sha1

    label = node.append("text").text((d) ->
        d.name
    ).each((d) ->
        b = @getBBox()

        # Calculate width/height of rectangle from text bounding box.
        d.rect_width = b.width + 2 * PADDING
        d.rect_height = b.height + 2 * PADDING

        # Now set the node width/height as used by cola for
        # positioning.  This has to include the margin
        # outside the rectangle.
        d.width = d.rect_width + 2 * RECT_MARGIN
        d.height = d.rect_height + 2 * RECT_MARGIN
    )

    position_nodes rect, label, tip

position_nodes = (rect, label, tip) ->
    rect.attr("width", (d, i) -> d.rect_width) \
        .attr("height", (d, i) -> d.rect_height) \
        .on("mouseover", tip.show) \
        .on("mouseout", tip.hide)

    # Centre label
    label \
        .attr("x", (d) -> d.rect_width / 2) \
        .attr("y", (d) -> d.rect_height / 2) \
        .on("mouseover", tip.show) \
        .on("mouseout", tip.hide)
    d3cola.start 10, 20, 20
    d3cola.on("tick", tick_handler)

    # d3cola.on("end", routeEdges);

    # turn on overlap avoidance after first convergence
    # d3cola.on("end", () ->
    #    unless d3cola.avoidOverlaps
    #        gdd.nodes.forEach((v) ->
    #            v.width = v.height = 10
    #        d3cola.avoidOverlaps true
    #        d3cola.start

update_rect_explored = () ->
    d3.selectAll(".node rect").attr "class", (d) ->
        if d.explored then "explored" else "unexplored"

tip_html = (d) ->
    fragment = $(tip_template).clone()
    top = fragment.find("#fragment")
    title = top.find("p.commit-title")
    title.text d.title

    if d.refs
        title.append "  <span />"
        refs = title.children().first()
        refs.addClass("commit-describe commit-ref") \
            .text(d.refs.join(" "))

    top.find("span.commit-author").text(d.author_name)
    date = new Date(d.author_time * 1000)
    top.find("time.commit-time") \
        .attr("datetime", date.toISOString()) \
        .text(date)
    pre = top.find(".commit-body pre").text(d.body)

    if options.debug
        # deps = gdd.deps[d.sha1]
        # if deps
        #     sha1s = [gdd.node(sha1).name for name, bool of deps]
        #     top.append("<br />Dependencies: " + sha1s.join(", "));
        index = gdd.node_index[d.sha1]
        debug = "<br />node index: " + index
        dagre_node = gdl.g.graph.node(d.sha1)
        debug += "<br />dagre: (#{dagre_node.x}, #{dagre_node.y})"
        top.append debug

    # Javascript *sucks*.  There's no way to get the outerHTML of a
    # document fragment, so you have to wrap the whole thing in a
    # single parent and then look that up via children[0].
    return fragment[0].children[0].outerHTML

translate = (x, y) ->
    "translate(#{x},#{y})"

tick_handler = ->
    node.each (d) ->
        # cola sets the bounds property which is a Rectangle
        # representing the space which other nodes should not
        # overlap.  The innerBounds property seems to tell
        # cola the Rectangle which is the visible part of the
        # node, minus any blank margin.
        d.innerBounds = d.bounds.inflate(-RECT_MARGIN)

    node.attr "transform", (d) ->
        translate d.innerBounds.x, d.innerBounds.y

    path.each (d) ->
        @parentNode.insertBefore this, this if isIE()

    path.attr "d", (d) ->

        # Undocumented: https://github.com/tgdwyer/WebCola/issues/52
        cola.vpsc.makeEdgeBetween \
            d,
            d.source.innerBounds,
            d.target.innerBounds,
            # This value is related to but not equal to the
            # distance of arrow tip from object it points at:
            5

        lineData = [
            {x: d.sourceIntersection.x, y: d.sourceIntersection.y},
            {x: d.arrowStart.x, y: d.arrowStart.y}
        ]
        return lineFunction lineData

lineFunction = d3.svg.line() \
    .x((d) -> d.x) \
    .y((d) -> d.y) \
    .interpolate("linear")

routeEdges = ->
    d3cola.prepareEdgeRouting EDGE_ROUTING_MARGIN
    path.attr "d", (d) ->
        lineFunction d3cola.routeEdge(d)
        # show visibility graph
        # (g) ->
        #    if d.source.id == 10 and d.target.id === 11
        #        g.E.forEach (e) =>
        #            vis.append("line").attr("x1", e.source.p.x).attr("y1", e.source.p.y)
        #                .attr("x2", e.target.p.x).attr("y2", e.target.p.y)
        #                .attr("stroke", "green")

    if isIE()
        path.each (d) ->
            @parentNode.insertBefore this, this

isIE = ->
    (navigator.appName is "Microsoft Internet Explorer") or
    ((navigator.appName is "Netscape") and
     ((new RegExp "Trident/.*rv:([0-9]{1,}[.0-9]{0,})")
        .exec(navigator.userAgent)?))
