const express = require("express");
const app = express();
const port = process.env.PORT || 3000;
app.get("/", (req, res) => {
  res.send(`Welcome to Expressapp`);
});
app.listen(port, () => {
  console.log(`helloworld: listening on port ${port}`);
});
