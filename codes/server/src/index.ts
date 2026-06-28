import { createApp } from "./app";

const port = Number(process.env.PORT ?? 3001);
const app = createApp();

app.listen(port, "0.0.0.0", () => {
  // eslint-disable-next-line no-console
  console.log(`Tessera server running on port ${port}`);
});
