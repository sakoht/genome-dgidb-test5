$('.tip').tooltip placement: 'right'

$('#loadingBar').show()
$.get '/gene_group_names.json', (data)->
  $('#geneInput').typeahead source: data, items: 20
  $('#loadingBar').hide()

$('#addGene').click ->
    geneInput = $('#geneInput')[0].value
    $('#genes')[0].value += geneInput + "\n" unless geneInput is ''
    $('#geneInput')[0].value = ''

$('#defaultGenes').click ->
    $('#genes')[0].value = ['FLT1','FLT2','FLT3','STK1','MM1','LOC100508755','FAKE1'].join "\n"
    $('#genes')[0].value += "\n"

$(".btn-primary").click ->
  $("#loading").modal("show")
