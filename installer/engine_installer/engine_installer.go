// Copyright 2017 VMware, Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"context"
	"fmt"
	"net/url"

	"github.com/vmware/vic/lib/install/data"
	"github.com/vmware/vic/lib/install/validate"
)

func main() {
	fmt.Println("hello world")

	ctx := context.TODO()

	//username := "administrator@vsphere.local"
	//password := "Admin!23"
	username := "root"
	password := "password"

	var u url.URL
	u.User = url.UserPassword(username, password)
	u.Host = "192.168.1.86"
	u.Path = ""
	fmt.Printf("server URL: %s\n", u)

	input := data.NewData()

	input.OpsUser = u.User.Username()
	passwd, _ := u.User.Password()
	input.OpsPassword = &passwd
	input.URL = &u
	input.Force = true

	input.User = username
	input.Password = &passwd
	fmt.Printf("%+v\n", input)

	validator, err := validate.NewValidator(ctx, input)
	if err != nil {
		fmt.Printf("validator: %s", err)
		return
	}

	dcs, err := validator.ListDatacenters()
	if err != nil {
		fmt.Println(err)
		return
	}
	for _, d := range dcs {
		fmt.Printf("DC: %s\n", d)
	}

}
