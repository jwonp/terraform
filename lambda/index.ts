import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
export const handler = async (event: APIGatewayProxyEvent) => {
  const response: APIGatewayProxyResult = {
    statusCode: 200,
    body: JSON.stringify({ id: "userID", name: "userName" }),
  };
  return response;
};
