import Chart from "chart.js"

function drawGraph(context, versionData) {
  let labels = []
  let data = [] 

  versionData.dd.forEach(function(dataPoint){
    labels.push(dataPoint.day)
    data.push(dataPoint.downloads)
  })

  new Chart(context,{
    type: "line",

    data: {
      labels: labels,
      datasets: [{
        label: versionData.r,
        backgroundColor: "rgb(79,40,167)",
        borderColor: "rgb(79,40,167)",
        data: data
      }]
    },

    options: {}
  })
}


export { drawGraph }
