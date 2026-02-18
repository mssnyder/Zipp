// Ported from apitaph — Google OpenID Connect profile extraction
import * as openidClient from "openid-client";

const { discovery } = openidClient;

let configPromise;

const getConfig = async () => {
  if (!configPromise) {
    configPromise = discovery(
      new URL("https://accounts.google.com"),
      process.env.GOOGLE_CLIENT_ID,
      { client_secret: process.env.GOOGLE_CLIENT_SECRET }
    );
  }
  return configPromise;
};

let profileImpl = async (tokens) => {
  const accessToken = tokens?.access_token;
  const idToken = tokens?.id_token || tokens?.raw?.id_token;

  if (!accessToken || !idToken) {
    throw new Error("Invalid OAuth response - missing tokens");
  }

  const config = await getConfig();

  let expectedSub;
  try {
    const payload = JSON.parse(Buffer.from(idToken.split(".")[1], "base64url").toString());
    expectedSub = payload.sub;
  } catch {
    throw new Error("Invalid ID token format");
  }

  const userInfo = await openidClient.fetchUserInfo(config, accessToken, expectedSub);
  const { sub, email, given_name: firstName, family_name: lastName } = userInfo;

  if (!sub || !email) throw new Error("Missing required Google profile fields");

  return { sub, email, firstName: firstName || "", lastName: lastName || "" };
};

export const getGoogleProfile = async (tokens) => profileImpl(tokens);
export const __setGoogleProfileImpl = (fn) => { profileImpl = fn; };
