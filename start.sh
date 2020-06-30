#!/bin/bash
mix run ./scripts/connect_to_builders.exs $CUSTOMER_NAME $BUILDER_REPLICAS $BUILDER_NAMESPACE

mix phx.server
