// INCLUDED FROM:
// xsl/html/coverage/genome_model.xsl
function render_coverage_chart() {

    cSummary.sort(cSummarySort);

    /* get chart data into nice arrays */
    var models = new Array();
    var model_ids = pv.keys(cSummary);
    var types = pv.keys(cSummary[model_ids[0]]);
    var depths = pv.keys(cSummary[model_ids[0]].pc_target_space_covered).sort(function(a,b) { return b-a });

    //convert full % to stacked %
    var coverage_data = []; // this will store the stacked version of the coverage data
    var coverage_data_full = []; // we'll need this to show the full instead of the stacked % in rollovers

    for (var model in cSummary) {
        models.push(cSummary[model].subject_name + " (L" + cSummary[model].lane + ")" );
        var full_depth_pc = [];
        var stacked_depth_pc = [];
        var i = 0;
        for (var depth in cSummary[model].pc_target_space_covered) {
            var stacked_depth; // stores the result of the full to stacked depth conversion
            var full_depth;
            if (i == 0) {
                // this highest depth w/ the lowest coverage, so it will be fully displayed.
                stacked_depth = cSummary[model].pc_target_space_covered[depths[i]];
                full_depth = stacked_depth;
            } else {
                // subtract lower depth from this depth
                stacked_depth = cSummary[model].pc_target_space_covered[depths[i]] -
                cSummary[model].pc_target_space_covered[depths[i-1]];
                full_depth = cSummary[model].pc_target_space_covered[depths[i]];
            }
            stacked_depth_pc.push(round(stacked_depth, 3));
            full_depth_pc.push(full_depth);
            i++;
        }
        coverage_data.push(stacked_depth_pc);
        coverage_data_full.push(full_depth_pc);
    }

    // protovis' Stack layout likes the data w/ one array per layer instead of one per column
    var coverage_data_t = pv.transpose(coverage_data);

    var coverage_w = 225,
        coverage_h = 16 * models.length,
        coverage_x = pv.Scale.linear(0, 100).range(0, coverage_w-10),
        coverage_y = pv.Scale.ordinal(pv.range(models.length)).splitBanded(0, coverage_h, .90);

    var c = pv.colors("#339900", "#66cc00", "#009999", "#33cccc", "#669999" );

    var coverage_vis = new pv.Panel()
        .width(coverage_w)
        .height(coverage_h)
        .bottom(0)
        .left(190)
        .right(10)
        .top(110);

    var bar = coverage_vis.add(pv.Layout.Stack)
        .layers(coverage_data_t)
        .orient("left-top")
        .x(function() { return coverage_y(this.index); } )
        .y(coverage_x)
        .layer.add(pv.Bar)
        .height(coverage_y.range().band)
        .fillStyle(function(d) { return c(this.parent.index); })
        .title(function() { return "depth: " + depths[this.parent.index] + "; target space covered: " + coverage_data_full[this.index][this.parent.index] + "%"; } );

    bar.anchor("right").add(pv.Label)
        .visible(function(d) { return this.parent.index == 0; }) // only show a label on the first layer
        .textStyle("white")
        .text(function(d) { return d.toFixed(1); } );

    bar.anchor("left").add(pv.Label)
        .visible(function() { return !this.parent.index; })
        .textMargin(5)
        .textAlign("right")
        .text(function() { return models[this.index]; });

    coverage_vis.add(pv.Rule)
        .data(coverage_x.ticks())
        .visible(function(d) { return d.toFixed() % 20 == 0 ? true : false; })
        .left(coverage_x)
        .strokeStyle(function(d) {
                             var color;
                             switch (d) {
                                 case 0:
                                     color = "#AAA";
                                 break;

                                 case 80: // highlight the 80% rule
                                     color = "#F00";
                                 break;

                                 case 100: // show the 100% rule
                                     color = "#CCC";
                                 break;

                                 default:
                                     color = "rgba(255,255,255,.3)";
                                 break;
                             }

                             return color;
                         })
        .add(pv.Rule)
        .top(0)
        .height(5)
        .strokeStyle("rgba(255,255,255,.3)")
        .anchor("top").add(pv.Label)
        .text(function(d) { return d.toFixed(); });

    // legend
    coverage_vis.add(pv.Panel)
        .top(-100)
        .left(-185)
        .add(pv.Dot)
        .data(depths)
        .top(function() { return this.index * 15; } )
        .size(8)
        .shape("square")
        .strokeStyle(null)
        .fillStyle(function(d) { return c(this.index); })
        .anchor("right").add(pv.Label)
        .text(function(d) { return "depth " + d; });

    // x axis label
    coverage_vis.add(pv.Label)
        .left(90)
        .font("bold 14px sans-serif")
        .top(-25)
        .text("coverage (%)");

    coverage_vis.render();

    function round(rnum, rlength) {
        return Math.round(rnum*Math.pow(10,rlength))/Math.pow(10,rlength);
    };

    function cSummarySort(a,b) {
        if (a.subject_name < b.subject_name) { return -1; };
        if (a.subject_name > b.subject_name) { return 1; };

        if (a.id < b.id) { return -1; };
        if (a.id > b.id) { return 1; };
        return 0;
    }
}